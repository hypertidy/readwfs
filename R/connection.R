#' Build a GDAL OGR connection for a vector web service
#'
#' Constructs the appropriate GDAL connection string from a base URL,
#' auto-detecting the service type (WFS, OAPIF, ArcGIS REST) or using
#' an explicit driver hint.
#'
#' @param base_url Character. The service endpoint URL.
#' @param driver Character. One of `"auto"`, `"WFS"`, `"OAPIF"`, `"ESRIJSON"`.
#'   When `"auto"`, the driver is inferred from the URL pattern.
#' @param version Character or `NULL`. WFS version (e.g. `"2.0.0"`). Ignored
#'   for non-WFS drivers.
#' @param srs Character or `NULL`. Target SRS as `"EPSG:XXXX"`. Passed as
#'   `srsName` for WFS.
#' @return A list with `dsn` (GDAL connection string) and `driver` (resolved
#'   driver name).
#' @keywords internal
wfs_connection <- function(base_url,
                           driver = c("auto", "WFS", "OAPIF", "ESRIJSON"),
                           version = NULL,
                           srs = NULL) {
  driver <- match.arg(driver)
  if (driver == "auto") {
    driver <- detect_driver(base_url)
  }
  dsn <- switch(driver,
    WFS = build_wfs_dsn(base_url, version = version, srs = srs),
    OAPIF = paste0("OAPIF:", strip_prefix(base_url)),
    ESRIJSON = paste0("ESRIJSON:", strip_prefix(base_url)),
    stop("Unsupported driver: ", driver, call. = FALSE)
  )
  list(dsn = dsn, driver = driver)
}

#' Detect the likely OGR driver from a URL
#'
#' @param url Character. Service URL.
#' @return Character. One of `"WFS"`, `"OAPIF"`, `"ESRIJSON"`.
#' @keywords internal
detect_driver <- function(url) {
  lc <- tolower(url)
  # Already prefixed
  if (startsWith(lc, "wfs:")) return("WFS")
  if (startsWith(lc, "oapif:")) return("OAPIF")
  if (startsWith(lc, "esrijson:")) return("ESRIJSON")
  # Pattern matching
  if (grepl("wfsserver|service=wfs", lc)) return("WFS")
  if (grepl("/collections|ogc/features", lc)) return("OAPIF")
  if (grepl("arcgis", lc) && grepl("featureserver|mapserver", lc)) {
    return("ESRIJSON")
  }
  "WFS"
}

#' Strip a GDAL driver prefix from a URL
#' @keywords internal
strip_prefix <- function(url) {
  sub("^(WFS|OAPIF|ESRIJSON):", "", url, ignore.case = TRUE)
}

#' Build a WFS connection string for capabilities / layer listing
#' @keywords internal
build_wfs_dsn <- function(base_url, version = NULL, srs = NULL) {
  url <- strip_prefix(base_url)
  if (!grepl("service=WFS", url, ignore.case = TRUE)) {
    sep <- if (grepl("\\?", url)) "&" else "?"
    url <- paste0(url, sep, "service=WFS")
  }
  if (!is.null(version) && !grepl("version=", url, ignore.case = TRUE)) {
    url <- paste0(url, "&version=", version)
  }
  if (!is.null(srs) && !grepl("srsName=", url, ignore.case = TRUE)) {
    url <- paste0(url, "&srsName=", srs)
  }
  paste0("WFS:", url)
}

#' Build a WFS GetFeature DSN with bbox/count in the URL
#' @keywords internal
build_wfs_read_dsn <- function(base_url, layer = NULL, bbox = NULL,
                               max_features = NULL, version = NULL,
                               srs = NULL) {
  url <- strip_prefix(base_url)
  if (!grepl("service=WFS", url, ignore.case = TRUE)) {
    sep <- if (grepl("\\?", url)) "&" else "?"
    url <- paste0(url, sep, "service=WFS")
  }
  params <- character(0)
  if (!grepl("request=", url, ignore.case = TRUE)) {
    params <- c(params, "request=GetFeature")
  }
  if (!is.null(version) && !grepl("version=", url, ignore.case = TRUE)) {
    params <- c(params, paste0("version=", version))
  }
  if (!is.null(srs) && !grepl("srsName=", url, ignore.case = TRUE)) {
    params <- c(params, paste0("srsName=", srs))
  }
  if (!is.null(layer) && !grepl("typeName", url, ignore.case = TRUE)) {
    params <- c(params, paste0("typeName=", layer))
  }
  if (!is.null(bbox)) {
    bbox_str <- paste(bbox, collapse = ",")
    if (!is.null(srs)) bbox_str <- paste0(bbox_str, ",", srs)
    params <- c(params, paste0("bbox=", bbox_str))
  }
  if (!is.null(max_features)) {
    params <- c(params, paste0("count=", as.integer(max_features)))
  }
  if (length(params) > 0) {
    url <- paste0(url, "&", paste(params, collapse = "&"))
  }
  paste0("WFS:", url)
}
