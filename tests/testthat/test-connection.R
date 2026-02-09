test_that("detect_driver identifies WFS URLs", {
  expect_equal(detect_driver("https://example.com/WFSServer"), "WFS")
  expect_equal(detect_driver("https://example.com?service=WFS"), "WFS")
  expect_equal(detect_driver("WFS:https://example.com/wfs"), "WFS")
})

test_that("detect_driver identifies ArcGIS REST URLs", {
  expect_equal(
    detect_driver("https://example.com/arcgis/rest/services/X/MapServer"),
    "ESRIJSON"
  )
  expect_equal(
    detect_driver("https://example.com/arcgis/rest/services/X/FeatureServer"),
    "ESRIJSON"
  )
})

test_that("detect_driver identifies OAPIF URLs", {
  expect_equal(
    detect_driver("https://example.com/ogc/features/collections"),
    "OAPIF"
  )
})

test_that("detect_driver defaults to WFS for unknown URLs", {
  expect_equal(detect_driver("https://example.com/some/endpoint"), "WFS")
})

test_that("strip_prefix removes driver prefixes", {
  expect_equal(strip_prefix("WFS:https://example.com"), "https://example.com")
  expect_equal(strip_prefix("ESRIJSON:https://example.com"), "https://example.com")
  expect_equal(strip_prefix("https://example.com"), "https://example.com")
})

test_that("build_wfs_dsn constructs valid connection strings", {
  dsn <- build_wfs_dsn("https://example.com/wfs")
  expect_match(dsn, "^WFS:")
  expect_match(dsn, "service=WFS")
})

test_that("build_wfs_dsn does not double-prefix", {
  dsn <- build_wfs_dsn("WFS:https://example.com/wfs")
  expect_false(grepl("WFS:WFS:", dsn))
})

test_that("build_wfs_dsn adds version and srs", {
  dsn <- build_wfs_dsn("https://example.com/wfs",
                       version = "2.0.0", srs = "EPSG:4326")
  expect_match(dsn, "version=2\\.0\\.0")
  expect_match(dsn, "srsName=EPSG:4326")
})

test_that("build_wfs_dsn does not duplicate existing params", {
  url <- "https://example.com/wfs?service=WFS&version=1.1.0"
  dsn <- build_wfs_dsn(url, version = "2.0.0")
  expect_equal(length(gregexpr("version=", dsn)[[1]]), 1)
})

test_that("build_wfs_read_dsn includes bbox and count", {
  dsn <- build_wfs_read_dsn(
    "https://example.com/wfs",
    layer = "myns:mylayer",
    bbox = c(1, 2, 3, 4),
    max_features = 100,
    version = "2.0.0",
    srs = "EPSG:4326"
  )
  expect_match(dsn, "^WFS:")
  expect_match(dsn, "bbox=1,2,3,4,EPSG:4326")
  expect_match(dsn, "count=100")
  expect_match(dsn, "typeName=myns:mylayer")
})

test_that("wfs_connection returns list with dsn and driver", {
  conn <- wfs_connection("https://example.com/WFSServer")
  expect_type(conn, "list")
  expect_named(conn, c("dsn", "driver"))
  expect_equal(conn$driver, "WFS")
})

test_that("wfs_connection respects explicit driver", {
  conn <- wfs_connection("https://example.com/whatever", driver = "ESRIJSON")
  expect_match(conn$dsn, "^ESRIJSON:")
  expect_equal(conn$driver, "ESRIJSON")
})
