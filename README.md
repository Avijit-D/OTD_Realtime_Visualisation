# Delhi Live Transit Tracker

A real-time bus tracking dashboard for Delhi built with R and Shiny. This application consumes live GTFS-Realtime binary feeds and integrates them with GTFS-Static metadata to provide an interactive map of the city's bus network.

---

## Features

* **Real-Time Tracking:** Polls the Delhi Open Transit Data (OTD) API every 10 seconds for live GPS coordinates of over 7,000 buses.
* **Intelligent Route Mapping:** Automatically translates internal API IDs into public route numbers (e.g., mapping 2100 to 534) using routes.txt.
* **Fleet Categorization:** Visualizes the fleet by agency with color-coded markers:
* **DTC (Public):** Standard Green/Red buses.
* **DIMTS (Cluster):** Orange buses.
* **Electric (EV):** New Blue/Teal electric fleet.


* **Anchored Search:** Smart filtering system using regex to find specific routes (e.g., searching "534" matches "534STL" but ignores "1534").
* **Bus Stop Overlay:** Toggleable layer showing all official bus stops from stops.txt to provide geographic context.

---

## Technical Decisions & Challenges

This project involved a deep dive into high-performance data processing in R. Key engineering decisions included:

### 1. Vectorized Data Ingestion

Initially, the app processed the Protocol Buffer feed row-by-row. To handle Delhi's massive fleet size, I refactored the logic to use Columnar Initialization. By pre-allocating atomic numeric vectors for latitude and longitude, the "time-to-map" was reduced significantly, preventing UI lag.

### 2. Defensive Programming & Data Sanitization

Real-time GPS feeds are often noisy. I implemented a sanitization pipeline:

* **Type Enforcement:** Forcing all coordinate data through as.numeric(unlist()) to prevent "list-type" errors in the Leaflet engine.
* **Geofencing:** Strictly filtering coordinates to a bounding box around Delhi to remove "ghost" markers caused by faulty GPS hardware.

### 3. Stateful vs. Stateless Architecture

While I initially explored adding "Bus Speed" (Stopped/Moving) categories, it was deprioritized. Calculating velocity requires comparing current snapshots to previous ones—a stateful process that introduced significant complexity and memory overhead for a real-time reactive Shiny app. The decision was made to prioritize Data Integrity over noisy, calculated metrics.

---

## Project Structure

```text
├── app.R                   # Main Shiny application code
├── gtfs-realtime.proto     # Protocol Buffer definition file
├── routes.txt              # Static route metadata (Required)
├── stops.txt               # Static stop metadata (Optional)
└── .env                    # Contains DELHI_API_KEY

```

---

## Setup & Installation

1. **Get an API Key:** Register at the Delhi Open Transit Data (OTD) portal.
2. **Download Static Data:** Place routes.txt and stops.txt in the root directory.
3. **Environment Variables:** Create a .env file or set your key in R:
```r
Sys.setenv(DELHI_API_KEY = "your_key_here")

```


4. **Install Dependencies:**
```r
install.packages(c("shiny", "leaflet", "httr", "RProtoBuf", "dplyr", "readr"))

```


5. **Run the App:**
```r
shiny::runApp()

```


---


## API Documentation

This application uses the Delhi Transport Corporation's GTFS-realtime API. For more information about the API, visit the DTC API documentation.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 
