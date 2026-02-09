test_that("wfs_example_url returns valid URLs", {
  expect_match(wfs_example_url("list_tasmania"), "^https://")
  expect_match(wfs_example_url("list_tasmania"), "WFSServer")
  expect_match(wfs_example_url("esri_sample"), "SampleWorldCities")
})

test_that("wfs_example_bbox returns named numeric length 4", {
  bb <- wfs_example_bbox("sandy_bay")
  expect_length(bb, 4)
  expect_named(bb, c("xmin", "ymin", "xmax", "ymax"))
  expect_true(bb["xmin"] < bb["xmax"])
  expect_true(bb["ymin"] < bb["ymax"])
})

test_that("wfs_services returns a tibble", {
  svc <- wfs_services()
  expect_s3_class(svc, "tbl_df")
  expect_true(nrow(svc) > 0)
  expect_true(all(c("name", "url", "driver", "region") %in% names(svc)))
})
