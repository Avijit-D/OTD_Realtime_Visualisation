# Realtime Bus Tracker

A Shiny application that displays real-time bus locations in Delhi using the Delhi Transport Corporation (DTC) API. The application shows bus positions on an interactive map that updates every 5 seconds.

## Features

- Real-time bus location tracking
- Interactive map interface using Leaflet
- Automatic updates every 5 seconds
- Bus information display (ID and route) on click
- Centered on Delhi with appropriate zoom level

## Prerequisites

- R (version 4.0.0 or higher)
- RStudio (recommended)
- DTC API key

## Required R Packages

```R
install.packages(c(
  "shiny",
  "leaflet",
  "httr",
  "RProtoBuf"
))
```

## Setup

1. Clone this repository
2. Open `app.R` in RStudio
3. Replace the API key in the code with your own:
   ```R
   api_key <- "YOUR_API_KEY"
   ```
4. Make sure the `gtfs-realtime.proto` file is in the correct location
5. Run the application

## Usage

1. Launch the application
2. The map will automatically load and center on Delhi
3. Bus locations will update every 5 seconds
4. Click on any bus marker to see its ID and route information

## API Documentation

This application uses the Delhi Transport Corporation's GTFS-realtime API. For more information about the API, visit the DTC API documentation.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 