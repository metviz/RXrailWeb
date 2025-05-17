library(shiny)
library(leaflet)
library(tidygeocoder)
library(osrm)
library(sf)
library(readr)
library(geosphere)

ui <- fluidPage(
  titlePanel("NC Railroad Crossings Route Map"),
  sidebarLayout(
    sidebarPanel(
      textInput("fromAddress", "From Address", "8624 Castleberry Rd, Apex, NC 27523"),
      textInput("toAddress", "To Address", "4000 Louis Stephens Dr, Cary, NC 27519"),
      actionButton("routeBtn", "Find Route"),
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
  
  output$railroadMap <- renderLeaflet({
    df <- crossings_data()
    leaflet(df) %>%
      addProviderTiles(providers$OpenStreetMap) %>%
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
    
    proxy <- leafletProxy("railroadMap")
    
    proxy %>%
      clearGroup("route") %>%
      addPolylines(data = st_zm(route), color = "blue", weight = 5, opacity = 0.9, group = "route") %>%
      setView(lng = from$long, lat = from$lat, zoom = 14)
    
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
    
    route_coords <- st_coordinates(route)[, 1:2]  # Only lon-lat
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
        title = "RXrail: Railroad Crossing Alert",
        paste("Warning: Your route is close to", length(near_crossings), "railroad crossing(s)."),
        easyClose = TRUE
      ))
    }
  })
}

shinyApp(ui, server)
