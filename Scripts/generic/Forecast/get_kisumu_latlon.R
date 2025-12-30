# install.packages("sf")
library(sf)

# Direct GeoJSON URL for Kenya ADM1 from HDX (geoBoundaries dataset)
geojson_url <- "https://data.humdata.org/dataset/geoboundaries-admin-boundaries-for-kenya/resource/131419b7-30ea-4d7d-a72b-e9cf6dcb4fb1/download/geoBoundaries-KEN-ADM1.geojson"

# Download to temporary file
tmpfile <- tempfile(fileext = ".geojson")
download.file(geojson_url, tmpfile, mode="wb")

# Read it as an sf object
kenya_adm1 <- st_read(tmpfile)

# See the names of admin regions
print(unique(kenya_adm1$shapeName))

# Filter Kisumu (case‑insensitive search)
kisumu <- kenya_adm1[grepl("Kisumu", kenya_adm1$shapeName, ignore.case = TRUE), ]

# Get bounding box
bbox_kisumu <- st_bbox(kisumu)
print(bbox_kisumu)

# Add a margin, e.g. 0.05 degrees
margin <- 0.05
bbox_kisumu_margin <- bbox_kisumu + c(-margin, -margin, margin, margin)
print(bbox_kisumu_margin)
