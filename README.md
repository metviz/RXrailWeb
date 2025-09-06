# RxRail-web

Shiny app to map NC railroad crossings (Can be extended to other states in US or other countries), plan a driving route, and warn when your route passes near rail lines or level crossings.

## Features
- Geocode two addresses with OpenStreetMap.
- Get a car route from OSRM.
- Switch between OpenStreetMap and Esri World Imagery tiles.
- Overlay OpenRailwayMap rails.
- Show time, distance, and turn-by-turn steps.
- Load local CSV of NC crossings and flag those within 300 m of the route.
- Query live OSM for level crossings and rail lines inside the route bbox.
- Alert if the route crosses a rail or runs parallel to it.

## Screenshots
<img width="1207" height="633" alt="image" src="https://github.com/user-attachments/assets/bac87236-fa5c-4c29-9851-bc3b2ab694b0" />
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/656cfc49-a3a3-4a00-a6c7-91a4cdc0cc85" />


## Requirements
- R 4.2+
- System libs for sf: GDAL, GEOS, PROJ
- Internet access for geocoding, tiles, OSRM, OSM

### R packages
```r
install.packages(c(
  "shiny", "leaflet", "tidygeocoder", "osrm", "sf",
  "readr", "geosphere", "osmdata", "jsonlite", "dplyr"
))
```

## Data
Place `NC_Railroad_crossing_data.csv` in the app working directory.

Minimum columns

| Column     | Type    | Notes   |
|------------|---------|---------|
| CrossingID | string  | Unique id |
| Latitude   | numeric | WGS84   |
| Longitude  | numeric | WGS84   |

Example
```csv
CrossingID,Latitude,Longitude
630123A,35.732700,-78.850300
630124B,35.740100,-78.843900
```

## Configuration
Routing backend
```r
options(osrm.server = "https://router.project-osrm.org/")
options(osrm.profile = "car")
```
Use your own OSRM for reliability. The public server can rate limit.

Map tiles
- Default: OpenStreetMap
- Satellite: Esri World Imagery (toggle in UI)

OpenRailwayMap overlay
```
http://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png
```
Some hosts block mixed content. If you serve the app over https, consider a proxy.

Proximity radius
- Default 300 meters. Edit `distances < 300` to change.

## Run locally
```r
shiny::runApp(".")
```
Or open in RStudio and click Run App.

Default demo addresses
- From: 8624 Castleberry Rd, Apex, NC 27523
- To: 4000 Louis Stephens Dr, Cary, NC 27519

## Project structure
```
.
├── app.R  # or ui.R + server.R using the code in this repo
├── NC_Railroad_crossing_data.csv
└── www/  # optional icons and assets
```

## Docker
Example container
```dockerfile
FROM rocker/shiny:4.4.1
RUN install2.r --error shiny leaflet tidygeocoder osrm sf readr geosphere osmdata jsonlite dplyr
COPY . /srv/shiny-server/rxrail
EXPOSE 3838
CMD ["/usr/bin/shiny-server"]
```
Mount your CSV at `/srv/shiny-server/rxrail/NC_Railroad_crossing_data.csv`.

## Deployment
**Shiny Server or ShinyProxy**
- Copy app files and CSV to the server.
- Allow outbound access to OSRM, OSM, OpenRailwayMap.

**RStudio Connect**
- Bundle the CSV with the app.

## How it works
1. Load CSV and init Leaflet with base tiles and OpenRailwayMap.
2. Geocode From and To with `tidygeocoder::geo(method = "osm")`.
3. Build `sf` points and call `osrmRoute(overview = "full")`.
4. Draw route line and start and end markers, fit bounds.
5. Call OSRM HTTP API for steps, render to `routeSteps`.
6. Compute Haversine distances from route points to CSV crossings, flag within radius.
7. Query OSM for level crossings and rail lines, label nodes, test route intersection or within 50 m for parallel.

## Troubleshooting
- Geocoding returns NA
  - Use simpler address strings. Try city plus street.
  - OSM may throttle. Retry later.
- OSRM errors
  - Public server can be down or limited. Deploy your own OSRM.
- sf build errors
  - Install GDAL, GEOS, PROJ. On Ubuntu: `apt install libgdal-dev libgeos-dev libproj-dev`.
- Missing railway overlay
  - OpenRailwayMap tiles can be slow. Check network or try again.
- Mixed content blocked
  - Serve all tiles over https or place behind a proxy.

## Privacy
- Address text goes to OSM geocoding.
- Coordinates go to OSRM.
- Do not log PII in production.

## Roadmap
- Filter markers by crossing type.
- Export near-crossing list as CSV.
- Cache geocoding and routes.
- Local OSRM container and retries.
- Better proximity using `sf::st_distance` with line geometry.

## Attribution
- OpenStreetMap contributors.
- Project OSRM.
- Esri World Imagery. Follow provider license.
- OpenRailwayMap. Follow provider license.

## License
MIT

## Contributing
- Open an issue with steps to reproduce.
- Use small PRs focused on one change.
- Add a short test route in your description.

## Maintainers
- RXrail team. Update contact info if you want public issues.
