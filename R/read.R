#' Read features from a vector web service
#'
#' Fetches vector features from a WFS, OGC API Features, or ArcGIS REST
#' endpoint and returns a tibble with a `wk::wkb` geometry column.
#'
#' @param base_url Character. The service endpoint URL.
#' @param layer Character. Layer name to read. Use [wfs_layers()] to
#'   discover available layers.
#' @param bbox Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`)
#'   or `NULL` for no spatial filter. Coordinates should be in the SRS
#'   specified by `srs` (or the layer's native SRS if `srs` is `NULL`).
#' @param max_features Integer or `NULL`. Maximum number of features to
#'   request. For WFS, passed as `count` in the URL. For other drivers,
#'   features are truncated after fetch.
#' @param where Character or `NULL`. An OGR SQL `WHERE` clause to filter
#'   features by attribute.
#' @param driver Character. Driver hint; see [wfs_connection()].
#' @param version Character or `NULL`. WFS version (e.g. `"2.0.0"`).
#' @param srs Character or `NULL`. Target SRS as `"EPSG:XXXX"`.
#' @param convert_linear Logical. If `TRUE` (default), convert
#'   circular arc geometries to linear approximations.
#' @param promote_to_multi Logical. If `TRUE`, promote single-part
#'   geometries to multi-part. Default `FALSE`.
#' @return A [tibble::tibble] with attribute columns and a `geometry`
#'   column of class `wk::wkb`.
#' @export
#' @examples
#' \dontrun{
#' # Tasmania LIST: cadastral parcels in Sandy Bay
#' parcels <- wfs_read(
#'   wfs_example_url("list_tasmania"),
#'   layer = "Public_OpenDataWFS:LIST_CADASTRAL_PARCELS",
#'   bbox = wfs_example_bbox("sandy_bay"),
#'   srs = "EPSG:28355",
#'   max_features = 100
#' )
#' parcels
#' wk::wk_plot(parcels$geometry)
#'
#' # Esri sample world cities
#' cities <- wfs_read(
#'   wfs_example_url("esri_sample"),
#'   layer = "esri:cities"
#' )
#' }
wfs_read <- function(base_url,
                     layer,
                     bbox = NULL,
                     max_features = NULL,
                     where = NULL,
                     driver = "auto",
                     version = NULL,
                     srs = NULL,
                     convert_linear = TRUE,
                     promote_to_multi = FALSE) {
  if (!is.null(bbox)) {
    stopifnot(is.numeric(bbox), length(bbox) == 4)
  }

  conn <- wfs_connection(base_url, driver = driver,
                         version = version, srs = srs)

  # For WFS, bake bbox/count into the URL (server-side filtering)
  # For ESRIJSON/OAPIF, use GDAL spatial filter (client-side or via REST)
  if (conn$driver == "WFS") {
    dsn <- build_wfs_read_dsn(
      base_url, layer = layer, bbox = bbox,
      max_features = max_features,
      version = version, srs = srs
    )
  } else {
    dsn <- conn$dsn
  }

  v <- new(gdalraster::GDALVector, dsn, layer, read_only = TRUE)
  on.exit(v$close(), add = TRUE)

  if (convert_linear) v$convertToLinear <- TRUE
  if (promote_to_multi) v$promoteToMulti <- TRUE

  # Attribute filter
  if (!is.null(where)) {
    v$setAttributeFilter(where)
  }

  # Spatial filter for non-WFS drivers (WFS handles it via URL)
  if (!is.null(bbox) && conn$driver != "WFS") {
    v$setSpatialFilterRect(bbox[1], bbox[2], bbox[3], bbox[4])
  }

  # Find geometry column from layer definition
  defn <- v$getLayerDefn()
  is_geom <- vapply(defn, function(f) isTRUE(f$is_geom), logical(1))
  geom_col <- if (any(is_geom)) names(defn)[which(is_geom)[1]] else NULL

  feat_count <- tryCatch(v$getFeatureCount(), error = function(e) -1L)

  message(sprintf(
    "Reading '%s': %s features, geometry column '%s'",
    layer,
    if (feat_count < 0) "unknown" else format(feat_count, big.mark = ","),
    geom_col %||% "(default)"
  ))

  raw <- v$fetch(-1)

  if (is.null(raw) || nrow(raw) == 0) {
    message("  0 features returned")
    return(empty_result())
  }

  # For non-WFS, truncate if max_features was requested
  if (!is.null(max_features) && conn$driver != "WFS") {
    if (nrow(raw) > max_features) {
      raw <- raw[seq_len(max_features), , drop = FALSE]
    }
  }

  result <- as_wk_tibble(raw, geom_col)
  message(sprintf("  %d features returned", nrow(result)))
  result
}

#' Convert raw fetch result to tibble with wk geometry
#' @keywords internal
as_wk_tibble <- function(raw, geom_col) {
  # Find the geometry column — may be named differently across drivers
  geom_name <- if (!is.null(geom_col) && geom_col %in% names(raw)) {
    geom_col
  } else {
    # Common fallbacks
    candidates <- c("SHAPE", "Shape", "shape", "GEOMETRY", "Geometry",
                     "geometry", "the_geom", "geom", "OGR_GEOMETRY",
                     "_ogr_geometry_")
    found <- intersect(candidates, names(raw))
    if (length(found) > 0) found[1]
    else {
      # Last resort: find the first list column containing raw vectors
      list_cols <- vapply(raw, is.list, logical(1))
      if (any(list_cols)) names(raw)[which(list_cols)[1]]
      else stop("Cannot identify geometry column in fetched data",
                call. = FALSE)
    }
  }

  geom <- wk::wkb(raw[[geom_name]])

  # Remove geometry and any all-NA FID column
  raw[[geom_name]] <- NULL
  if ("FID" %in% names(raw) && all(is.na(raw[["FID"]]))) {
    raw[["FID"]] <- NULL
  }

  tbl <- tibble::as_tibble(raw)
  tbl$geometry <- geom
  tbl
}

#' Create an empty result tibble
#' @keywords internal
empty_result <- function() {
  tibble::tibble(geometry = wk::wkb(list()))
}
