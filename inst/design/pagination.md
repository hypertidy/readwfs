# Pagination design for readwfs

## Problem

WFS servers impose limits on how many features they return per request. Tasmania LIST caps at around 3,000. Esri defaults to 1,000-2,000. A user asking for "all parcels in Hobart" might need 50,000+ features but only get the first page silently truncated. This is the single most common WFS footgun.

## How pagination works across drivers

### WFS 2.0 (the good case)

WFS 2.0 added `startIndex` and `count` to GetFeature. The server also reports its default and maximum page size in GetCapabilities under `<ows:Constraint name="CountDefault">`.

Request pattern:
```
&startIndex=0&count=1000    -> features 0-999
&startIndex=1000&count=1000 -> features 1000-1999
...
```

The response includes `numberMatched` (total available) and `numberReturned` (this page). When `numberReturned < count` or `numberReturned == 0`, you're done.

GDAL's WFS driver can handle this automatically if you set the `OGR_WFS_PAGING_ALLOWED=YES` config option and `OGR_WFS_PAGE_SIZE=N`. When paging is enabled, `v$fetch(-1)` transparently pages through the full result set. This is the easiest path.

### WFS 1.1 / 1.0 (no standard paging)

No `startIndex`. The only control is `maxFeatures`. Some servers support vendor extensions (GeoServer has `startIndex` even in 1.1), but it's not standardised. GDAL still attempts paging on GeoServer instances.

### ArcGIS REST / ESRIJSON

ArcGIS FeatureServer/MapServer has `resultOffset` and `resultRecordCount`. GDAL's ESRIJSON driver handles paging automatically  --  it reads the `exceededTransferLimit` flag in the JSON response and fetches subsequent pages. No user intervention needed for `v$fetch(-1)`.

### OAPIF (OGC API Features)

Built-in paging via `limit` and `offset` query params, or `next` link in the response. GDAL's OAPIF driver follows `next` links automatically.

## Current readwfs behaviour

`wfs_read()` calls `v$fetch(-1)` which asks GDAL for all features. Whether that actually gets all features depends on:

1. Whether GDAL's paging is enabled for the driver
2. The server's max page size
3. Whether the user's `max_features` caps the request first

Right now there's **no warning when results are truncated**. A user gets back 1,000 features and may not realise there were 50,000 available.

## Proposed design

### Option A: Let GDAL handle it (minimal intervention)

Set `OGR_WFS_PAGING_ALLOWED=YES` and a sensible `OGR_WFS_PAGE_SIZE` before opening the connection. GDAL pages transparently. ESRIJSON and OAPIF already page automatically.

Pros: Simple, no custom pagination code.
Cons: No progress reporting, no control over memory, can't stream/process in chunks.

Implementation:
```r
# In wfs_read(), before opening GDALVector:
gdalraster::set_config_option("OGR_WFS_PAGING_ALLOWED", "YES")
gdalraster::set_config_option("OGR_WFS_PAGE_SIZE", as.character(page_size))
# ... open and fetch as normal ...
# Restore config after
```

### Option B: Manual pagination with progress

Page explicitly using `startIndex`/`count` in the URL, collect results, rbind. Gives us control over progress bars and memory.

```r
wfs_read(..., page_size = 1000, progress = TRUE)
```

Loop:
```r
offset <- 0
pages <- list()
repeat {
  dsn <- build_wfs_read_dsn(..., start_index = offset, max_features = page_size)
  v <- new(GDALVector, dsn, layer)
  page <- v$fetch(-1)
  v$close()
  if (is.null(page) || nrow(page) == 0) break
  pages <- c(pages, list(page))
  offset <- offset + nrow(page)
  if (!is.null(max_features) && offset >= max_features) break
  if (nrow(page) < page_size) break
  message(sprintf("  fetched %d features...", offset))
}
do.call(rbind, pages)
```

Pros: Progress, control, can cap memory.
Cons: WFS-specific, doesn't help ESRIJSON/OAPIF, more code, potentially slower than GDAL's internal paging.

### Option C: Hybrid (recommended)

- Default: enable GDAL's paging config options and let `v$fetch(-1)` do its thing (Option A). This works across all drivers.
- Add a **truncation warning**: after fetch, compare `nrow(result)` against `v$getFeatureCount()`. If the count was known and we got fewer, warn.
- Add `page_size` parameter to `wfs_read()` that sets `OGR_WFS_PAGE_SIZE`. Default to something sensible like 2000.
- Future: if someone needs chunked processing (memory pressure), add `wfs_read_chunked()` that yields pages via a callback.

## Truncation detection

The key user-facing improvement. After fetching:

```r
expected <- v$getFeatureCount()  
actual <- nrow(result)

if (expected > 0 && actual < expected) {
  warning(sprintf(
    "Only %d of %d features returned. The server may have a page size limit. ",
    "Try setting page_size or check OGR_WFS_PAGING_ALLOWED.",
    actual, expected
  ), call. = FALSE)
}
```

This catches the silent truncation problem regardless of pagination strategy.

## Config options reference

| Option | Default | Effect |
|---|---|---|
| `OGR_WFS_PAGING_ALLOWED` | `""` (auto) | `"YES"` forces paging on |
| `OGR_WFS_PAGE_SIZE` | driver default | Features per page |
| `OGR_WFS_LOAD_MULTIPLE_LAYER_DEFN` | `"TRUE"` | Load all layer defs at once (faster discovery, more memory) |
| `OGR_WFS_BASE_START_INDEX` | `"0"` | Some servers use 1-based indexing |

## Questions to resolve during testing

1. Does `gdalraster::set_config_option()` persist across GDALVector instances or is it truly global? Need to save/restore.
2. Does `v$getFeatureCount()` return the **total** or the **page** count when paging is active? (Should be total for WFS 2.0 with `numberMatched`.)
3. How does Tasmania LIST behave with `OGR_WFS_PAGING_ALLOWED=YES`? What's its actual page size limit?
4. Does the Esri sample server support WFS paging or just ESRIJSON paging?
5. For ESRIJSON, does `v$fetch(-1)` already page automatically or do we need to enable something?

## Implementation priority

1. **Truncation warning**  --  highest value, lowest effort. Do this first.
2. **Enable GDAL paging by default**  --  set config options in `wfs_read()`.
3. **`page_size` parameter**  --  expose control to the user.
4. **`wfs_read_chunked()`**  --  only if someone needs it for memory reasons.
