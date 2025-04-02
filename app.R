library(shiny)
library(leaflet)
library(httr)
library(RProtoBuf)

# API Setup
# Replace with your own API key from DTC
api_key <- "YOUR_API_KEY"
api_url <- paste0("https://otd.delhi.gov.in/api/realtime/VehiclePositions.pb?key=", api_key)

# Load the GTFS-realtime protobuf schema
proto_path <- "gtfs-realtime.proto"
readProtoFiles(proto_path)

fetch_bus_data <- function() {
  response <- GET(api_url)
  if (status_code(response) != 200) stop("Failed to fetch data.")
  
  protobuf_data <- content(response, "raw")
  if (length(protobuf_data) == 0) stop("Received empty response.")
  
  parsed_data <- tryCatch({
    P("transit_realtime.FeedMessage")$read(protobuf_data)
  }, error = function(e) stop("Error parsing protobuf message."))
  
  buses <- lapply(parsed_data$entity, function(entity) {
    if (!is.null(entity$vehicle)) {
      list(
        id = entity$vehicle$vehicle$id,
        latitude = entity$vehicle$position$latitude,
        longitude = entity$vehicle$position$longitude,
        route = entity$vehicle$trip$route_id
      )
    }
  })
  
  return(Filter(Negate(is.null), buses))
}

ui <- fluidPage(
  leafletOutput("busMap")
)

server <- function(input, output, session) {
  bus_data <- reactivePoll(5000, session,
                           checkFunc = function() { Sys.time() },
                           valueFunc = function() { fetch_bus_data() }
  )
  
  output$busMap <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = 77.2167, lat = 28.6448, zoom = 12)
  })
  
  observe({
    buses <- bus_data()
    if (!is.null(buses) && length(buses) > 0) {
      leafletProxy("busMap") %>% clearMarkers()
      for (bus in buses) {
        leafletProxy("busMap") %>%
          addMarkers(
            lng = bus$longitude,
            lat = bus$latitude,
            popup = paste("Bus ID:", bus$id, "<br>Route:", bus$route)
          )
      }
    }
  })
}

shinyApp(ui, server) 