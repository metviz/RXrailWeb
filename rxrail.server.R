library(shiny)
library(leaflet)
library(readr)
library(tidygeocoder)
library(geosphere)

# Define UI
ui <- fluidPage(
  titlePanel("NC Railroad Crossings Map with Route Highlight"),
  sidebarLayout(
    sidebarPanel(
      textInput("fromAddress", "From Address"),
      textInput("toAddress", "To Address"),
      actionButton("routeBtn", "Find Route and Highlight")
    ),
    mainPanel(
      leafletOutput("railroadMap", height = "600px")
    )
  )
)

# Define Server
server <- function(input, output, session) {
  # Read CSV Data
  crossings_data <- reactive({
    read_csv("NC_Railroad_crossing_data.csv", show_col_types = FALSE)
  })
  
  # Initialize Map with default zoom to Apex, NC
  output$railroadMap <- renderLeaflet({
    df <- crossings_data()
    leaflet(df) %>%
      addTiles() %>%
      setView(lng = -78.8503, lat = 35.7327, zoom = 12) %>%  # Apex, NC coordinates
      addCircleMarkers(~Longitude, ~Latitude,
                       popup = ~paste("CrossingID:", CrossingID, "<br>",
                                      "State:", StateName),
                       radius = 5, color = "red", fillOpacity = 0.8)
  })
  
  # Highlight route and check proximity
  observeEvent(input$routeBtn, {
    req(input$fromAddress, input$toAddress)
    
    from_coords <- geo(input$fromAddress, method = "osm")
    to_coords <- geo(input$toAddress, method = "osm")
    
    if (is.na(from_coords$lat) || is.na(to_coords$lat)) {
      showModal(modalDialog(
        title = "Geocoding Error",
        "Unable to geocode one or both addresses. Please try again.",
        easyClose = TRUE
      ))
      return()
    }
    
    # Generate intermediate points (SpatialLines)
    line_points <- gcIntermediate(c(from_coords$long, from_coords$lat),
                                  c(to_coords$long, to_coords$lat),
                                  n = 200, addStartEnd = TRUE, sp = TRUE)
    
    # Extract coordinates from SpatialLines
    route_coords <- line_points@lines[[1]]@Lines[[1]]@coords
    
    leafletProxy("railroadMap") %>%
      clearGroup("route") %>%
      addPolylines(lng = route_coords[,1], lat = route_coords[,2], 
                   color = "blue", weight = 5, opacity = 0.8, group = "route")
    
    crossings <- crossings_data()
    crossing_coords <- cbind(crossings$Longitude, crossings$Latitude)
    
    distances <- distm(route_coords, crossing_coords, fun = distHaversine)
    
    if (any(distances < 500)) {
      showModal(modalDialog(
        title = "Railroad Crossing Alert",
        "Warning: There are railroad crossings close to your route!",
        easyClose = TRUE
      ))
    } else {
      showModal(modalDialog(
        title = "Route Check",
        "Your route does not pass close to any railroad crossings.",
        easyClose = TRUE
      ))
    }
  })
  
}

# Run Shiny App
shinyApp(ui, server)
