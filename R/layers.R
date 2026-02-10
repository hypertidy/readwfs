#' List available layers from a vector web service
#'
#' Queries the service endpoint and returns the names of all available
#' feature types / layers.
#'
#' @param base_url Character. The service endpoint URL. Can be a raw URL
#'   or a GDAL-prefixed connection string (e.g. `"WFS:https://..."`).
#' @param driver Character. One of `"auto"`, `"WFS"`, `"OAPIF"`, `"ESRIJSON"`.
#' @param version Character or `NULL`. WFS version.
#' @param srs Character or `NULL`. Target SRS.
#' @return A character vector of layer names.
#' @export
#' @examples
#' \dontrun{
#' # Tasmania LIST WFS
#' wfs_layers(wfs_example_url("list_tasmania"))
#'
#' # Esri sample WFS
#' wfs_layers(wfs_example_url("esri_sample"))
#' }
wfs_layers <- function(base_url, driver = "auto", version = NULL, srs = NULL) {
  conn <- wfs_connection(base_url, driver = driver,
                         version = version, srs = srs)
  gdalraster::ogr_ds_layer_names(conn$dsn)
}

#' Search layer names by pattern
#'
#' A convenience wrapper around [wfs_layers()] that filters results with
#' `grep()`. Useful when a service has dozens or hundreds of layers.
#'
#' @inheritParams wfs_layers
#' @param pattern Character. A regular expression to match against layer names.
#' @param ignore.case Logical. Passed to [grep()].
#' @return A character vector of matching layer names.
#' @export
#' @examples
#' \dontrun{
#' url <- wfs_example_url("list_tasmania")
#' wfs_find_layers(url, "CADASTRAL|TASVEG")
#' }
wfs_find_layers <- function(base_url, pattern, driver = "auto",
                            version = NULL, srs = NULL,
                            ignore.case = TRUE) {
  layers <- wfs_layers(base_url, driver = driver,
                       version = version, srs = srs)
  grep(pattern, layers, value = TRUE, ignore.case = ignore.case)
}

#' Get layer metadata from a vector web service
#'
#' Returns a tibble describing each layer: geometry type, feature count
#' (if available), spatial extent, and spatial reference.
#'
#' @inheritParams wfs_layers
#' @param layers Character vector of layer names to inspect, or `NULL`
#'   to inspect all layers. Inspecting all layers can be slow for large
#'   services -- consider using [wfs_find_layers()] first.
#' @return A [tibble::tibble] with columns: `name`, `geom_column`,
#'   `geom_type`, `feature_count`, `xmin`, `ymin`, `xmax`, `ymax`, `srs_wkt`.
#' @export
#' @examples
#' \dontrun{
#' url <- wfs_example_url("list_tasmania")
#' wfs_layer_info(url, layers = "Public_OpenDataWFS:LIST_Cadastral_Parcels",
#'                version = "2.0.0", srs = "EPSG:28355")
#' }
wfs_layer_info <- function(base_url, layers = NULL, driver = "auto",
                           version = NULL, srs = NULL) {
  conn <- wfs_connection(base_url, driver = driver,
                         version = version, srs = srs)

  if (is.null(layers)) {
    layers <- gdalraster::ogr_ds_layer_names(conn$dsn)
  }

  rows <- lapply(layers, function(lyr) {
    tryCatch(
      layer_info_one(conn$dsn, lyr),
      error = function(e) {
        tibble::tibble(
          name = lyr, geom_column = NA_character_,
          geom_type = NA_character_, feature_count = NA_integer_,
          xmin = NA_real_, ymin = NA_real_,
          xmax = NA_real_, ymax = NA_real_,
          srs_wkt = NA_character_
        )
      }
    )
  })

  do.call(rbind, rows)
}

#' Inspect a single layer via GDALVector
#' @keywords internal
#' @importFrom methods new
layer_info_one <- function(dsn, layer_name) {
  v <- new(gdalraster::GDALVector, dsn, layer_name, read_only = TRUE,
           open_options = "TRUST_CAPABILITIES_BOUNDS=YES")
  on.exit(v$close(), add = TRUE)

  defn <- v$getLayerDefn()
  is_geom <- vapply(defn, function(f) isTRUE(f$is_geom), logical(1))
  geom_fields <- defn[is_geom]

  if (length(geom_fields) > 0) {
    gf <- geom_fields[[1]]
    geom_col <- names(geom_fields)[1]
    geom_type <- gf$type
    srs_wkt <- gf$srs
  } else {
    geom_col <- NA_character_
    geom_type <- NA_character_
    srs_wkt <- NA_character_
  }

  feat_count <- tryCatch(v$getFeatureCount(), error = function(e) NA_integer_)
  ext <- tryCatch(v$bbox(), error = function(e) rep(NA_real_, 4))

  tibble::tibble(
    name = layer_name,
    geom_column = geom_col,
    geom_type = geom_type %||% NA_character_,
    feature_count = as.integer(feat_count),
    xmin = ext[1], ymin = ext[2], xmax = ext[3], ymax = ext[4],
    srs_wkt = if (is.character(srs_wkt) && nzchar(srs_wkt)) srs_wkt else NA_character_
  )
}

#' Get field (column) information for a layer
#'
#' Returns a tibble describing each non-geometry field in a layer:
#' name, type, width, and whether it's nullable.
#'
#' @param base_url Character. The service endpoint URL.
#' @param layer Character. Layer name.
#' @param driver,version,srs Passed to [wfs_connection()].
#' @return A [tibble::tibble] with columns: `name`, `type`, `width`,
#'   `precision`, `is_nullable`.
#' @export
#' @examples
#' \dontrun{
#' url <- wfs_example_url("list_tasmania")
#' wfs_fields(url, "Public_OpenDataWFS:LIST_Cadastral_Parcels",
#'            version = "2.0.0", srs = "EPSG:28355")
#' }
wfs_fields <- function(base_url, layer, driver = "auto",
                       version = NULL, srs = NULL) {
  conn <- wfs_connection(base_url, driver = driver,
                         version = version, srs = srs)

  v <- new(gdalraster::GDALVector, conn$dsn, layer, read_only = TRUE)
  on.exit(v$close(), add = TRUE)

  defn <- v$getLayerDefn()
  # defn is a named list of lists. Each element is a field definition.
  # Attribute fields have: type, subtype, width, precision, is_nullable,
  #   is_unique, default, domain, is_geom (FALSE)
  # Geometry fields have: type, srs, is_nullable, is_geom (TRUE)

  # Keep only non-geometry fields
  is_geom <- vapply(defn, function(f) isTRUE(f$is_geom), logical(1))
  attr_defn <- defn[!is_geom]

  if (length(attr_defn) == 0) {
    return(tibble::tibble(
      name = character(), type = character(), subtype = character(),
      width = integer(), precision = integer(),
      is_nullable = logical(), is_unique = logical()
    ))
  }

  tibble::tibble(
    name = names(attr_defn),
    type = vapply(attr_defn, `[[`, character(1), "type"),
    subtype = vapply(attr_defn, `[[`, character(1), "subtype"),
    width = vapply(attr_defn, function(f) as.integer(f$width), integer(1)),
    precision = vapply(attr_defn, function(f) as.integer(f$precision), integer(1)),
    is_nullable = vapply(attr_defn, `[[`, logical(1), "is_nullable"),
    is_unique = vapply(attr_defn, `[[`, logical(1), "is_unique")
  )
}

