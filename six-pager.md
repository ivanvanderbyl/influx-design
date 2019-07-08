# Design Goals

<!-- @import "[TOC]" {cmd="toc" depthFrom=1 depthTo=6 orderedList=false} -->

We want to achieve superior analytics of time series data with the following characteristics.

## Aggregation on read

We want to minimize aggregation on write, and maximise aggregation on read where practical. In practice, aggregation on read will occur in InfluxDB during queries with InfluxQL and/or Flux.

The client (Flow) should not be expected to aggregate time series data. This will minimise data round trips / data sent over the wire and maximise the functionality of InfluxDB itself.

## Aggregation on write

It is not practical to write raw point data to InfluxDB due to high write volumes and rates from the tools themselves, hence we need to accept a minimum form of aggregation on write.

Aggregation occurs on Grid Nodes via Kapacitor, as part of their current UDP stream processing (tool emits data to Kapacitor via UDP).

Further aggregation will occur on InfluxDB, as part of pipe line processing (Drain, Pipe) and continuous queries in order to maximise efficiency of write throughput, retention policy and shard management.

## Transformation Functions

Flux’s built-in transformation functions will transform or shape data as follows.

### Flux aggregate functions

Flux aggregate functions will take values from an input table and aggregate then as follows:

- The count() function outputs the number of records in each aggregated column. It counts both null and non-null records.

```
  Function type: Aggregate
  Output data type: Integer
  Example: 4069 passed transactions
```

Flux selector functions
Flux selector functions return one or more records based on function logic.

Aggregations such as min, max, count and sum should be 100% accurate to the original data. Examples include:

- min response time = 2,051 ms
- max concurrency = 1,000 users
- count passed = 4,069 transactions
- sum network = 492,092 bytes received

These will occur on Grid Nodes via Kapacitor and be accurately written into InfluxDB.

Aggregations such as mean will naturally included standard error (standard deviation of its sampling distribution), and further aggregations of the same measurements will decrease accuracy and precision of results. We will write higher precision aggregates for new data (recent floods) and move to lower precision aggregates for older data (older floods). For aggregates such as mean we will also highlight standard deviation. Examples include:

- mean response time = 2,324 ms over 1s period
- stddev response time = 2,324 ms over 1s period
- mean response time = 2,000 ms over 15s period

Aggregations such as histograms will be


Aggregations such as quantiles

## Minimise responsibility of the tool

We want to minimise the responsibility of tool e.g. JMeter in terms of aggregation and labelling so that it emits the minimum amount of data needed to be consumed by Flood.

Ideally the tool should emit 'common' measurements such as response time, concurrency, passed, failed and traces. Measurements are typically emitted at the test step level, with the exception of concurrency, which is emitted at the test case level.

The tool should not be concerned with other tag sets related to operation of the tool itself. This is the responsibility of the aggregation point, typically the grid node.

### Provide alternative ways to emit data

We want to provide alternative options for the tool to emit data, aside from the current UDP streams, to increase the options available to customers for emitting data. For example, uploading a test result as a file or the ability read a file descriptor streams (stdin, stdout, stderr).

## Series

Measurements are produced by the tool (JMeter, Gatling, Element etc), aggregated by the node (Kapacitor) and then written via a pipe line (Drain, Pipe) to the time series database (InfluxDB).

Measurements are scoped to the individual test step / transaction level, and also at the test case level for any grid node. Series are the collection of data in the InfluxDB that share a measurement, tag set, and retention policy.

Series can also be derived from tool / grid produced measurements, to facilitate easier/faster querying or produce transformations useful to the UI.

Series cardinality are the number of unique database, measurement, tag set, and field key combinations in InfluxDB.

### Test step series

- response_time: mean of elapsed time
  - tags:
    - label_id: _string_ sequential label ID of step
    - type: _string_ step,stepWithThinkTime, network, timeToFirstInteractive, timeToFirstByte
  - fields:
    - value: _float_ time in milliseconds
- passed: count of passed
  - tags:
    - label_id: _string_ sequential label ID of step
  - fields:
    - value: _int_ total count
- failed: count of failed
  - tags:
    - label_id: _string_ sequential label ID of step
  - fields:
    - value: _int_ total count

### Test case series

- concurrency: count of active users
  - fields:
    - value: _int_ total count
- network_rx: sum of network received bytes
  - fields:
    - value: _int_ total bytes
- network_tx: sum of network transmitted bytes
  - fields:
    - value: _int_ total bytes

### Derived measurements

 - transaction_rate: non negative derivative expressed as transactions per second, based on sum of passed and failed measurements
   - fields
     - value: _float_


### Out of scope measurements

Out of scope for this design document, but under consideration, are measurements with high dimensionality / cardinality, such as server side monitoring and/or tracing.

Handling of these measurements will be covered in another design document and most likely include their own schema design and data management.

# Schema Design

InfluxDB. schema design will be heavily influenced [recommended schema design and data layout](https://docs.influxdata.com/InfluxDB/v1.7/concepts/schema_and_data_layout)

That is:

1. encode metadata in tags
2. avoid using InfluxQL as identifiers
3. don't have too many series
4. don't encode data in measurement names
5. don't put more than one piece of information in one tag

# Precision Periods

We want s

A [WindowNode](https://docs.influxdata.com/kapacitor/v1.5/nodes/window_node/#sidebar) covers the time range of the aggregation at the GridNode. Historically we have used a WindowNode with a period of 15s. For the purpose of this document, 15s is considered low precision.


the accuracy of a measurement system is the degree of closeness of measurements of a quantity to that quantity's true value

The precision of a measurement system, related to reproducibility and repeatability, is the degree to which repeated measurements under unchanged conditions show the same results

There is no math for meaningfully aggregating percentiles. Once we have aggregated data at the GridNode, even if we write the percentile, the typical averaging of percentiles is completely bogus.

A design goal for this epic is to write higher precision data to InfluxDB, for the following reasons:

- 15s is a relatively long time to wait for results to appear in a live flood.
- Accuracy of 15s aggregations


We are aiming for an LPP of:

| Period | RP Duration | Shard Group Duration |
|-------:|------------:|---------------------:|
| 1s     | 1mo         | 7d                   |
| 15s    | 12mo        | 52w                  |


High Precision

1s  1mo
Low Precision
15s 52w

CREATE RETENTION POLICY "one_month" ON "results" DURATION 4w REPLICATION 1 DEFAULT
CREATE RETENTION POLICY "one_year" ON "results" DURATION 52w REPLICATION 1

Shard groups should be twice as long as the longest time range of the most frequent queries
Shard groups should each contain more than 100,000 points per shard group
Shard groups should each contain more than 1,000 points per series

# Anticipated Measurements

Measurements are always pre-aggregated by the node, before being written to InfluxDB. The following measurements and aggregations are anticipated in the lowest possible time window.

- response_time: mean of elapsed time for a transaction
- concurrency: max of active users
- passed: sum of passed transactions
- failed: sum of failed transactions
