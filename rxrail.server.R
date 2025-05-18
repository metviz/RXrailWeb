library(shiny)
library(leaflet)
library(tidygeocoder)
library(osrm)
library(sf)
library(readr)
library(geosphere)
library(osmdata)

ui <- fluidPage(
  titlePanel("NC Railroad Crossings Route Map"),
  sidebarLayout(
    sidebarPanel(
      textInput("fromAddress", "From Address", "8624 Castleberry Rd, Apex, NC 27523"),
      textInput("toAddress", "To Address", "4000 Louis Stephens Dr, Cary, NC 27519"),
      actionButton("routeBtn", "Find Route"),
      checkboxInput("satelliteView", "Use Satellite View", value = FALSE),
      hr(),
      verbatimTextOutput("routeInfo"),
      verbatimTextOutput("routeSteps")
    ),
    mainPanel(
      leafletOutput("railroadMap", height = "600px")
    )
  )
)

server <- function(input, output, session) {
  
  options(osrm.server = "https://router.project-osrm.org/")
  options(osrm.profile = "car")
  
  crossings_data <- reactive({
    read_csv("NC_Railroad_crossing_data.csv", show_col_types = FALSE)
  })
  
  baseMap <- reactive({
    if (input$satelliteView) {
      providers$Esri.WorldImagery
    } else {
      providers$OpenStreetMap
    }
  })
  
  output$railroadMap <- renderLeaflet({
    df <- crossings_data()
    leaflet(df) %>%
      addProviderTiles(baseMap()) %>%
      addTiles(urlTemplate = "http://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png",
               attribution = "© OpenStreetMap contributors, Style: CC-BY-SA 2.0 OpenRailwayMap",
               options = tileOptions(minZoom = 2, maxZoom = 19, tileSize = 256)) %>%
      setView(lng = -78.8503, lat = 35.7327, zoom = 13) %>%
      addCircleMarkers(~Longitude, ~Latitude, data = df,
                       radius = 5, color = "red", fillOpacity = 0.8,
                       popup = ~paste("CrossingID:", CrossingID))
  })
  
  observeEvent(input$routeBtn, {
    req(input$fromAddress, input$toAddress)
    
    from <- geo(input$fromAddress, method = "osm", verbose = FALSE)
    to <- geo(input$toAddress, method = "osm", verbose = FALSE)
    
    if (anyNA(from$lat) || anyNA(from$long) || anyNA(to$lat) || anyNA(to$long)) {
      showModal(modalDialog(
        title = "Geocoding Error",
        "Unable to geocode one or both addresses. Please check your input.",
        easyClose = TRUE
      ))
      return()
    }
    
    src <- st_sf(id = "src", geometry = st_sfc(st_point(c(from$long, from$lat)), crs = 4326))
    dst <- st_sf(id = "dst", geometry = st_sfc(st_point(c(to$long, to$lat)), crs = 4326))
    
    route <- tryCatch({
      osrmRoute(src = src, dst = dst, overview = "full")
    }, error = function(e) {
      showModal(modalDialog(
        title = "Routing Error",
        paste("Failed to retrieve route:", e$message),
        easyClose = TRUE
      ))
      return(NULL)
    })
    
    if (is.null(route)) return()
    
    midpoint <- c(mean(c(from$lat, to$lat)), mean(c(from$long, to$long)))
    bbox <- st_bbox(route)
    
    proxy <- leafletProxy("railroadMap") %>%
      clearGroup("route") %>%
      clearMarkers() %>%
      addProviderTiles(baseMap()) %>%
      addPolylines(data = st_zm(route), color = "blue", weight = 5, opacity = 0.9, group = "route") %>%
      addMarkers(lng = from$long, lat = from$lat, popup = "Start", icon = makeIcon("https://maps.google.com/mapfiles/ms/icons/green-dot.png")) %>%
      addMarkers(lng = to$long, lat = to$lat, popup = "Destination", icon = makeIcon("https://maps.google.com/mapfiles/ms/icons/red-dot.png")) %>%
      fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]])
    
    output$routeInfo <- renderText({
      paste("Estimated time:", round(route$duration, 1), "minutes\n",
            "Estimated distance:", round(route$distance, 2), "km")
    })
    
    url <- sprintf("https://router.project-osrm.org/route/v1/driving/%.6f,%.6f;%.6f,%.6f?overview=false&steps=true",
                   from$long, from$lat, to$long, to$lat)
    steps_json <- jsonlite::fromJSON(url)
    
    if (!is.null(steps_json$routes)) {
      instructions <- steps_json$routes[[1]]$legs[[1]]$steps
      if (length(instructions) > 0) {
        step_texts <- paste(seq_along(instructions$maneuver$instruction), ". ", instructions$maneuver$instruction, sep = "")
        output$routeSteps <- renderText({
          paste("Turn-by-turn directions:\n", paste(step_texts, collapse = "\n"))
        })
      }
    }
    
    route_coords <- st_coordinates(route)[, 1:2]
    crossings <- crossings_data()
    crossing_coords <- cbind(crossings$Longitude, crossings$Latitude)
    distances <- distm(route_coords, crossing_coords, fun = distHaversine)
    near_crossings <- unique(which(distances < 300, arr.ind = TRUE)[, 2])
    
    if (length(near_crossings) > 0) {
      proxy %>%
        addCircleMarkers(data = crossings[near_crossings, ],
                         lng = ~Longitude, lat = ~Latitude,
                         radius = 6, color = "orange", fillColor = "yellow", fillOpacity = 0.9,
                         popup = ~paste("Warning! Close Crossing:", CrossingID),
                         group = "near_crossings")
      
      showModal(modalDialog(
        title = "Railroad Crossing Alert",
        paste("Warning: Your route is close to", length(near_crossings), "railroad crossing(s)."),
        easyClose = TRUE
      ))
    }
    
    # Query OSM railway lines in bounding box
    railway_query <- opq(bbox = bbox) %>%
      add_osm_feature(key = "railway", value = c("rail", "tram"))
    
    rail_sf <- tryCatch({
      osmdata_sf(railway_query)$osm_lines
    }, error = function(e) NULL)
    
    if (!is.null(rail_sf) && nrow(rail_sf) > 0) {
      crossing_segs <- st_intersects(route, rail_sf, sparse = FALSE)
      parallel_segs <- st_is_within_distance(route, rail_sf, dist = 50, sparse = FALSE)
      
      status <- if (any(crossing_segs)) {
        "Your route crosses a railway."
      } else if (any(parallel_segs)) {
        "Your route runs parallel to a railway."
      } else {
        "No rail interaction detected."
      }
      
      showModal(modalDialog(
        title = "Rail Interaction Info",
        status,
        easyClose = TRUE
      ))
    }
  })
}

shinyApp(ui, server)
