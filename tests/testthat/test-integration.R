# These tests hit real WFS endpoints and are skipped on CRAN
# and when offline. Run locally with: testthat::test_file("test-integration.R")

test_that("wfs_layers works for Tasmania LIST", {
  skip_if_offline()
  skip_on_cran()

  layers <- wfs_layers(
    wfs_example_url("list_tasmania"),
    version = "2.0.0",
    srs = "EPSG:28355"
  )

  expect_type(layers, "character")
  expect_true(length(layers) > 0)
  expect_true(any(grepl("CADASTRAL", layers)))
})

test_that("wfs_find_layers filters correctly", {
  skip_if_offline()
  skip_on_cran()

  found <- wfs_find_layers(
    wfs_example_url("list_tasmania"),
    pattern = "CADASTRAL",
    version = "2.0.0",
    srs = "EPSG:28355"
  )

  expect_type(found, "character")
  expect_true(length(found) > 0)
  expect_true(all(grepl("CADASTRAL", found, ignore.case = TRUE)))
})

test_that("wfs_read returns tibble with wk geometry for Tasmania", {
  skip_if_offline()
  skip_on_cran()

  parcels <- wfs_read(
    wfs_example_url("list_tasmania"),
    layer = "Public_OpenDataWFS:LIST_CADASTRAL_PARCELS",
    bbox = wfs_example_bbox("sandy_bay"),
    srs = "EPSG:28355",
    max_features = 10
  )

  expect_s3_class(parcels, "tbl_df")
  expect_true("geometry" %in% names(parcels))
  expect_s3_class(parcels$geometry, "wk_wkb")
  expect_true(nrow(parcels) > 0)
  expect_true(nrow(parcels) <= 10)
})

test_that("wfs_layer_info returns metadata tibble", {
  skip_if_offline()
  skip_on_cran()

  info <- wfs_layer_info(
    wfs_example_url("list_tasmania"),
    layers = "Public_OpenDataWFS:LIST_CADASTRAL_PARCELS",
    version = "2.0.0",
    srs = "EPSG:28355"
  )

  expect_s3_class(info, "tbl_df")
  expect_equal(nrow(info), 1)
  expect_true("name" %in% names(info))
  expect_true("feature_count" %in% names(info))
})

test_that("wfs_fields returns schema for a layer", {
  skip_if_offline()
  skip_on_cran()

  fields <- wfs_fields(
    wfs_example_url("list_tasmania"),
    layer = "Public_OpenDataWFS:LIST_CADASTRAL_PARCELS",
    version = "2.0.0",
    srs = "EPSG:28355"
  )

  expect_s3_class(fields, "tbl_df")
  expect_true(nrow(fields) > 0)
  expect_true("name" %in% names(fields))
})

test_that("Esri sample WFS works", {
  skip_if_offline()
  skip_on_cran()

  layers <- wfs_layers(wfs_example_url("esri_sample"))
  expect_type(layers, "character")
  expect_true(length(layers) > 0)
})
