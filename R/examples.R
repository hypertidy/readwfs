#' Example service endpoint URLs
#'
#' Pre-configured URLs for example services used in documentation,
#' vignettes, and testing.
#'
#' @param service Character. One of:
#'   - `"list_tasmania"`: Tasmania LIST open data WFS (parcels, vegetation,
#'     local government areas, hydro, transport, and more)
#'   - `"esri_sample"`: Esri SampleWorldCities WFS (continents, cities —
#'     small dataset, always available)
#' @return A character string with the service URL.
#' @export
#' @examples
#' wfs_example_url("list_tasmania")
#' wfs_example_url("esri_sample")
wfs_example_url <- function(service = c("list_tasmania", "esri_sample")) {
  service <- match.arg(service)
  switch(service,
    list_tasmania = paste0(
      "https://services.thelist.tas.gov.au/arcgis/services/",
      "Public/OpenDataWFS/MapServer/WFSServer"
    ),
    esri_sample = paste0(
      "https://sampleserver6.arcgisonline.com/arcgis/services/",
      "SampleWorldCities/MapServer/WFSServer"
    )
  )
}

#' Example bounding boxes
#'
#' Pre-configured bounding boxes for example areas.
#'
#' @param area Character. One of:
#'   - `"sandy_bay"`: Sandy Bay, Hobart — EPSG:28355 (MGA Zone 55), ~600m x 600m
#'   - `"hobart"`: Greater Hobart — EPSG:28355, ~10km x 10km
#' @return A named numeric vector (`xmin`, `ymin`, `xmax`, `ymax`).
#' @export
#' @examples
#' wfs_example_bbox("sandy_bay")
#' wfs_example_bbox("hobart")
wfs_example_bbox <- function(area = c("sandy_bay", "hobart")) {
  area <- match.arg(area)
  switch(area,
    sandy_bay = c(xmin = 523800, ymin = 5250400, xmax = 524400, ymax = 5251000),
    hobart = c(xmin = 519000, ymin = 5247000, xmax = 529000, ymax = 5257000)
  )
}

#' Catalogue of known public vector web services
#'
#' Returns a tibble of known, tested public services that work with readwfs.
#' This isn't exhaustive — it's a starting point. If you find a good one,
#' open an issue.
#'
#' @return A [tibble::tibble] with columns: `name`, `url`, `driver`,
#'   `region`, `description`, `srs`, `notes`.
#' @export
#' @examples
#' wfs_services()
#'
#' # Try one
#' \dontrun{
#' svc <- wfs_services()
#' wfs_layers(svc$url[1])
#' }
wfs_services <- function() {
  tibble::tribble(
    ~name, ~url, ~driver, ~region, ~description, ~srs, ~notes,

    "LIST Tasmania",
    paste0("https://services.thelist.tas.gov.au/arcgis/services/",
           "Public/OpenDataWFS/MapServer/WFSServer"),
    "WFS", "Tasmania, Australia",
    "Cadastral parcels, vegetation (TASVEG), LGA boundaries, transport, hydro",
    "EPSG:28355",
    "Rich service, 100+ layers. Use version='2.0.0'",

    "Esri SampleWorldCities",
    paste0("https://sampleserver6.arcgisonline.com/arcgis/services/",
           "SampleWorldCities/MapServer/WFSServer"),
    "WFS", "Global",
    "Continents and world cities — small demo dataset",
    "EPSG:4326",
    "Always available, good for testing. Esri-hosted sample server"
  )
}
