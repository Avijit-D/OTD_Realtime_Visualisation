library(shiny)
library(leaflet)
library(httr)
library(RProtoBuf)
library(dplyr)
library(readr)

# ==============================
# API CONFIG
# ==============================
api_key <- Sys.getenv("DELHI_API_KEY")
if (api_key == "") stop("Set DELHI_API_KEY first")

api_url <- paste0(
  "https://otd.delhi.gov.in/api/realtime/VehiclePositions.pb?key=",
  api_key
)

# ==============================
# 1. LOAD STATIC DATA
# ==============================
static_data <- list(routes = NULL, stops = NULL)

tryCatch({
  message("Loading Static Data...")
  
  if (file.exists("routes.txt")) {
    static_data$routes <- read_csv(
      "routes.txt",
      show_col_types = FALSE,
      col_types = cols(.default = "c")
    ) %>%
      select(route_id, route_short_name, route_long_name) %>%
      distinct(route_id, .keep_all = TRUE)
  }
  
  if (file.exists("stops.txt")) {
    static_data$stops <- read_csv(
      "stops.txt",
      show_col_types = FALSE,
      col_types = cols(stop_lat = "d", stop_lon = "d", .default = "c")
    ) %>%
      select(stop_name, stop_lat, stop_lon) %>%
      filter(!is.na(stop_lat) & !is.na(stop_lon))
  }
  
}, error = function(e) {
  warning("Error loading static files: ", e$message)
})

# ==============================
# 2. GTFS PROTO SETUP
# ==============================
proto_path <- "gtfs-realtime.proto"
if (!file.exists(proto_path)) {
  download.file(
    "https://raw.githubusercontent.com/google/transit/master/gtfs-realtime/proto/gtfs-realtime.proto",
    destfile = proto_path,
    mode = "wb"
  )
}

if (!exists("transit_realtime.FeedMessage", where = "RProtoBuf:DescriptorPool")) {
  readProtoFiles(proto_path)
}

# ==============================
# 3. FETCH REAL-TIME DATA
# ==============================
fetch_bus_data <- function() {
  
  tryCatch({
    res <- GET(api_url, timeout(10))
    if (status_code(res) != 200) return(NULL)
    
    feed <- P("transit_realtime.FeedMessage")$read(content(res, "raw"))
    entities <- feed$entity
    n <- length(entities)
    if (n == 0) return(NULL)
    
    ids   <- character(n)
    lats  <- numeric(n)
    lngs  <- numeric(n)
    r_ids <- character(n)
    
    for (i in seq_len(n)) {
      v <- entities[[i]]$vehicle
      if (!is.null(v)) {
        
        ids[i] <- if (!is.null(v$vehicle$id)) as.character(v$vehicle$id) else "Unknown"
        r_ids[i] <- if (!is.null(v$trip$route_id)) as.character(v$trip$route_id) else "Unknown"
        
        if (!is.null(v$position$latitude) && !is.null(v$position$longitude)) {
          lats[i] <- as.numeric(v$position$latitude)
          lngs[i] <- as.numeric(v$position$longitude)
        } else {
          lats[i] <- NA_real_
          lngs[i] <- NA_real_
        }
      } else {
        lats[i] <- NA_real_
        lngs[i] <- NA_real_
      }
    }
    
    bus_df <- data.frame(
      id = ids,
      lat = lats,
      lng = lngs,
      route_id = r_ids,
      stringsAsFactors = FALSE
    )
    
    # Strict cleanup
    bus_df <- bus_df %>%
      filter(!is.na(lat) & !is.na(lng)) %>%
      filter(lat > 10 & lat < 40 & lng > 60 & lng < 90)
    
    if (nrow(bus_df) == 0) return(NULL)
    
    # Merge route names
    if (!is.null(static_data$routes)) {
      bus_df <- left_join(bus_df, static_data$routes, by = "route_id")
      
      bus_df$display_name <- ifelse(
        !is.na(bus_df$route_short_name),
        bus_df$route_short_name,
        bus_df$route_id
      )
      
      bus_df$desc <- ifelse(
        !is.na(bus_df$route_long_name),
        bus_df$route_long_name,
        ""
      )
    } else {
      bus_df$display_name <- bus_df$route_id
      bus_df$desc <- ""
    }
    
    # Fleet decoding
    bus_df <- bus_df %>%
      mutate(
        agency = case_when(
          grepl("^DL51", id) ~ "Electric (EV)",
          grepl("DL1PC", id) ~ "DIMTS (Cluster)",
          TRUE ~ "DTC (Public)"
        ),
        color = case_when(
          agency == "Electric (EV)" ~ "#2563eb",
          agency == "DIMTS (Cluster)" ~ "#f97316",
          TRUE ~ "#16a34a"
        ),
        popup_html = paste0(
          "<div style='font-family:sans-serif; font-size:13px;'>",
          "<b>Route:</b> ", display_name, "<br>",
          "<span style='font-size:11px; color:grey;'>", desc, "</span><br>",
          "<b>Bus ID:</b> ", id, "<br>",
          "<b>Fleet:</b> <span style='color:", color, "'>", agency, "</span><br>",
          "<hr style='margin:5px 0;'>",
          "<a href='https://www.google.com/maps?q=", lat, ",", lng, "' target='_blank'>Open Maps</a>",
          "</div>"
        )
      )
    
    return(bus_df)
    
  }, error = function(e) {
    message("Fetch error: ", e$message)
    return(NULL)
  })
}

# ==============================
# UI
# ==============================
ui <- fluidPage(
  titlePanel("Delhi Live Transit Tracker"),
  
  sidebarLayout(
    sidebarPanel(
      textInput("route_search", "Search Route:", placeholder = "e.g. 534"),
      textInput("bus_search", "Search Bus ID:", placeholder = "e.g. DL1PC..."),
      checkboxInput("cluster", "Cluster Bus Markers", TRUE),
      checkboxInput("show_stops", "Show All Bus Stops (Yellow)", FALSE),
      hr(),
      uiOutput("status_msg"),
      hr(),
      h4("Fleet Stats"),
      tableOutput("fleet_stats")
    ),
    mainPanel(
      leafletOutput("map", height = "85vh")
    )
  )
)

# ==============================
# SERVER
# ==============================
server <- function(input, output, session) {
  
  bus_data <- reactivePoll(
    10000,
    session,
    checkFunc = function() Sys.time(),
    valueFunc = fetch_bus_data
  )
  
  output$status_msg <- renderUI({
    if (!is.null(static_data$routes)) {
      tags$div(style="color:green; font-weight:bold;", "✔ Real Names Active")
    } else {
      tags$div(style="color:red;", "✖ routes.txt Missing")
    }
  })
  
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      setView(77.21, 28.64, 11) %>%
      addLegend(
        "bottomright",
        colors = c("#f97316", "#16a34a", "#2563eb"),
        labels = c("DIMTS", "DTC", "EV")
      )
  })
  
  # Stops Layer
  observe({
    leafletProxy("map") %>% clearGroup("stops")
    
    if (input$show_stops && !is.null(static_data$stops)) {
      leafletProxy("map") %>%
        addCircleMarkers(
          data = static_data$stops,
          lng = ~stop_lon, lat = ~stop_lat,
          radius = 2,
          color = "#E5C100",
          fillColor = "#FFD700",
          fillOpacity = 0.6,
          stroke = FALSE,
          label = ~stop_name,
          group = "stops"
        )
    }
  })
  
  # Bus Layer - FIXED
  observe({
    bus_df <- bus_data()
    req(bus_df)
    
    # --- LOGIC FIX HERE ---
    if (nzchar(input$route_search)) {
      # Use `^` to match the START of the string only.
      # This ensures "534" matches "534STL" but ignores "1534"
      bus_df <- bus_df %>%
        filter(grepl(paste0("^", input$route_search), display_name, ignore.case = TRUE))
    }
    
    if (nzchar(input$bus_search)) {
      bus_df <- bus_df %>%
        filter(grepl(input$bus_search, id, ignore.case = TRUE))
    }
    # ----------------------
    
    if (nrow(bus_df) == 0) {
      leafletProxy("map") %>% clearGroup("buses")
      return()
    }
    
    proxy <- leafletProxy("map") %>% clearGroup("buses")
    
    # We define the marker logic once to keep code clean
    if (input$cluster) {
      proxy %>%
        addCircleMarkers(
          data = bus_df,
          lng = ~lng, lat = ~lat,
          radius = 6, stroke = FALSE,
          fillColor = ~color, fillOpacity = 0.8,
          label = ~id, popup = ~popup_html,
          group = "buses",
          clusterOptions = markerClusterOptions()
        )
    } else {
      proxy %>%
        addCircleMarkers(
          data = bus_df,
          lng = ~lng, lat = ~lat,
          radius = 6, stroke = FALSE,
          fillColor = ~color, fillOpacity = 0.8,
          label = ~id, popup = ~popup_html,
          group = "buses"
        )
    }
  })
  
  output$fleet_stats <- renderTable({
    df <- bus_data()
    if (is.null(df)) return(NULL) # Safety check
    df %>% group_by(Agency = agency) %>% summarise(Count = n(), .groups = "drop")
  })
}

shinyApp(ui, server)
