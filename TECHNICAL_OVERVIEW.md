# Delhi Live Transit Tracker

## Building a Real-Time GTFS-Realtime Visualization System in R

## Project Overview

This project involved building a real-time transit visualization system for Delhi’s bus network using **R** and **Shiny**.

The original goal was simple:

> Visualize live bus locations on an interactive map.

However, transforming raw **GTFS-Realtime Protocol Buffer data** into a stable, interpretable, and performant system required solving challenges across:

* Binary data decoding
* Schema alignment
* Performance optimization
* Defensive programming
* UI scalability
* Real-time data sanitation

What began as “plotting dots on a map” evolved into an exercise in building a production-grade reactive telemetry system.

---

# 1. Data Architecture & Integration

The system integrates two distinct data streams:

## 1.1 Dynamic Stream - GTFS-Realtime

* Source: Delhi Open Transit Data (OTD)
* Format: Protocol Buffer (`VehiclePositions.pb`)
* Contains:

  * Vehicle ID
  * Latitude/Longitude
  * Internal `route_id`
* Snapshot-based feed (not stateful)

### Constraint:

The realtime feed only provides internal identifiers.
It does **not** provide user-readable route names.

---

## 1.2 Static Stream - GTFS Static Files

* `routes.txt`
* `stops.txt`

These files contain:

* `route_short_name`
* `route_long_name`
* Stop coordinates

### Why Static Data Matters

Realtime feed alone is not interpretable:

```
route_id = 2100
```

To users, this is meaningless.

By joining static GTFS metadata with the realtime feed, internal IDs were mapped to public-facing route numbers (e.g., `534`).

This transformed raw telemetry into usable commuter information.

---

# 2. Realtime Data Processing Strategy

## 2.1 Protobuf Decoding

GTFS-Realtime is delivered in binary format.
The system uses `RProtoBuf` to decode:

```r
P("transit_realtime.FeedMessage")$read(...)
```

The `.proto` file is auto-downloaded if missing to ensure portability.

---

## 2.2 From Row-Wise to Columnar Processing

### Initial Implementation

* Iterated over entities
* Built a growing list of records
* Converted list to dataframe

At ~7,000 vehicles, performance degraded significantly.

### Refactor: Vectorized Columnar Initialization

Instead of growing lists, the system pre-allocates atomic vectors:

```r
ids   <- character(n)
lats  <- numeric(n)
lngs  <- numeric(n)
r_ids <- character(n)
```

Then fills them in a single pass.

### Why This Matters

R performs best with atomic vectors and columnar memory layouts.
This refactor:

* Reduced memory fragmentation
* Decreased object copying
* Improved rendering latency
* Stabilized high-volume updates

This was a turning point in performance.

---

# 3. Defensive Data Engineering

## 3.1 The “Invalid Type (List)” Crash

During rendering, Leaflet repeatedly crashed with:

```
invalid 'type' (list) of argument
```

### Root Cause

Protocol Buffers occasionally returned list-wrapped numeric values or NULL fields.
Leaflet’s `expandLimits()` expects atomic numeric vectors.

Even one list-type element in `lat` or `lng` caused the entire render pipeline to fail.

---

### Solution: Aggressive Sanitization

The ingestion pipeline now enforces:

* Explicit `as.numeric()` coercion
* NA filtering
* Geographic bounding box filter (Delhi only)
* Strict atomic dataframe construction

This eliminated runtime rendering crashes.

---

## 3.2 Schema Alignment

Joining realtime and static data initially caused silent mismatches.

Problem:

* Static `route_id` loaded as character
* Realtime `route_id` occasionally numeric

Solution:

* Force both to `character`
* Join only after type alignment

This ensured stable relational joins across 7,000+ entities.

---

# 4. UI Scalability & Search Precision

## 4.1 The “Mixed Search” Conflict

Searching for `534` returned:

* 534
* 1534
* 2534

Cause:

```r
grepl("534", route)
```

Fix:

```r
grepl("^534", route)
```

Anchored regex ensures start-of-string match while allowing variants like `534A`.

This improved search precision and user trust.

---

## 4.2 Route Dropdown Scalability Problem

A multi-select dropdown with hundreds of routes caused:

* UI lag
* Shiny warnings
* Heavy DOM rendering

Solution:
Replaced dropdown with text-based route search.

This:

* Scales infinitely
* Reduces UI overhead
* Improves responsiveness

---

# 5. Fleet Decoding & Domain Enrichment

The raw feed provides vehicle IDs.

Using ID patterns:

```r
grepl("^DL51", id) → Electric
grepl("DL1PC", id) → DIMTS (Cluster)
```

This enabled:

* Fleet classification
* Color-coded visualization
* Real-time fleet distribution stats

Raw telemetry was enriched into operational insight.

---

# 6. Rendering Strategy & Performance

## 6.1 Snapshot Architecture

The system polls every 10 seconds using:

```r
reactivePoll()
```

Each cycle:

* Fetch snapshot
* Sanitize
* Clear group
* Redraw markers

### Why Not Incremental Diff?

Incremental updates require:

* Stateful memory
* Vehicle position tracking
* Complex synchronization

Given scale and constraints, snapshot redraw was simpler and sufficiently performant.

---

## 6.2 Canvas Rendering

Leaflet default SVG struggled with 1,000+ markers.

Enabled:

```r
leafletOptions(preferCanvas = TRUE)
```

Result:

* Smoother pan/zoom
* Lower CPU overhead
* Stable clustering behavior

---

# 7. Feature Trade-Off: Velocity Logic

Initial plan:
Classify buses as:

* Stopped
* Slow
* Moving

### Why It Was Removed

1. API speed field unreliable.
2. Snapshot feed cannot compute velocity without state.
3. Proper velocity tracking requires:

   * Storing previous coordinates
   * Matching IDs
   * Handling drift and latency
   * Managing memory for thousands of vehicles

This introduced architectural complexity disproportionate to value.

Decision:
Prioritize data integrity over speculative feature logic.

---

# 8. Memory Constraints & Static Data Strategy

The `stop_times.txt` file exceeds 100MB.

Loading it entirely:

* Increases memory footprint
* Slows startup
* Risky on free-tier Shiny servers

Proposed solution:
Representative Trip Sampling:

* Select one `trip_id` per `route_id`
* Preserve route geometry
* Avoid heavy dataset loading

Demonstrates performance-aware system design.

---

# 9. Stability Safeguards

The system implements:

* HTTP status checks
* tryCatch on all IO
* Static file existence checks
* NA filtering
* Geographic validation
* Conditional clustering
* req() guards in observers
* Atomic type enforcement

Result:
No known crash path under malformed feed conditions.

---

# 10. Final System Behavior

The completed system:

1. Polls the OTD API every 10 seconds.
2. Decodes Protocol Buffers.
3. Sanitizes and enforces atomic data types.
4. Aligns schema and joins static metadata.
5. Applies fleet classification.
6. Supports anchored route and bus search.
7. Provides optional stop overlay.
8. Displays real-time clustering and fleet statistics.

---

# 11. What This Project Demonstrates

This project reflects competence in:

* Binary protocol ingestion
* Real-time reactive systems
* Performance optimization in R
* Memory-aware design
* Schema alignment strategy
* Defensive programming
* UI scalability design
* Trade-off evaluation
* Feature prioritization discipline

---

# Closing Technical Reflection

The original objective was to visualize buses.

The actual outcome was learning how to build a system that:

* Survives malformed data
* Scales under load
* Respects memory constraints
* Preserves interpretability
* Prioritizes stability over novelty

This project became less about mapping buses and more about engineering judgment.
You can find that story here : [Medium Link](https://medium.com/@avijit168d/untitled-document-md-bd5dc0a21b48)

