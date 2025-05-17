library(shiny)
library(leaflet)
library(tidygeocoder)
library(geosphere)

ui <- fluidPage(
  titlePanel("NC Railroad Crossings Route Map"),
  sidebarLayout(
    sidebarPanel(
      textInput("fromAddress", "From Address", ""),
      textInput("toAddress", "To Address", ""),
      actionButton("routeBtn", "Find Route")
    ),
    mainPanel(
      leafletOutput("railroadMap", height = "600px")
    )
  )
)

server <- function(input, output, session) {
  
  output$railroadMap <- renderLeaflet({
    leaflet() %>%
      addProviderTiles(providers$OpenStreetMap) %>%
      setView(lng = -78.8503, lat = 35.7327, zoom = 13)  # Apex, NC
  })
  
  observeEvent(input$routeBtn, {
    req(input$fromAddress, input$toAddress)
    
    from_coords <- geo(input$fromAddress, method = "osm", verbose = FALSE)
    to_coords <- geo(input$toAddress, method = "osm", verbose = FALSE)
    
    if (is.na(from_coords$lat) || is.na(to_coords$lat)) {
      showModal(modalDialog(
        title = "Geocoding Error",
        "Unable to geocode one or both addresses. Please check your input.",
        easyClose = TRUE
      ))
      return()
    }
    
    # Generate intermediate points for the route
    route_line <- gcIntermediate(
      c(from_coords$long, from_coords$lat),
      c(to_coords$long, to_coords$lat),
      n = 200,
      addStartEnd = TRUE,
      sp = TRUE
    )
    
    # Extract coordinates for plotting
    route_coords <- route_line@lines[[1]]@Lines[[1]]@coords
    
    # Update map with route line
    leafletProxy("railroadMap") %>%
      clearGroup("route") %>%
      addPolylines(
        lng = route_coords[,1], 
        lat = route_coords[,2],
        color = "blue", weight = 5, opacity = 0.8, group = "route"
      ) %>%
      fitBounds(
        lng1 = min(route_coords[,1]), lat1 = min(route_coords[,2]),
        lng2 = max(route_coords[,1]), lat2 = max(route_coords[,2])
      )
  })
}

shinyApp(ui, server)
