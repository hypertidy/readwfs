
## readwfs 0.1.0

Initial development version.

* `wfs_read()` reads vector features from WFS, OAPIF, and ArcGIS REST
  endpoints into tibbles with `wk::wkb` geometry columns.
* `wfs_layers()` and `wfs_find_layers()` for service discovery and
  layer name search.
* `wfs_layer_info()` returns geometry type, feature count, and extent
  from service metadata (fast, no feature download).
* `wfs_fields()` returns the attribute schema for a layer.
* `wfs_services()` provides a catalogue of known public endpoints.
* Auto-detection of service type (WFS, OAPIF, ESRIJSON) from URL patterns.
* Safe default `max_features = 10000` with informative message when
  more features are available.
* WFS paging enabled by default for ~6x speedup on large fetches.
* Uses `TRUST_CAPABILITIES_BOUNDS` for fast extent queries.
* Example URLs and bounding boxes for Tasmania LIST and Esri
  SampleWorldCities via `wfs_example_url()` and `wfs_example_bbox()`.
