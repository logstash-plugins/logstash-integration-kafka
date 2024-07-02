## 11.5.0
  - Add "auto_create_topics" option to allow disabling of topic auto creation [#172](https://github.com/logstash-plugins/logstash-integration-kafka/pull/172)

## 11.4.2
  - Add default client_id of logstash to kafka output [#169](https://github.com/logstash-plugins/logstash-integration-kafka/pull/169)

## 11.4.1
  - [DOC] Match anchor ID and references for `message_headers` [#164](https://github.com/logstash-plugins/logstash-integration-kafka/pull/164)

## 11.4.0
  - Add support for setting Kafka message headers in output plugin [#162](https://github.com/logstash-plugins/logstash-integration-kafka/pull/162)

## 11.3.4
  - Fix "retries" and "value_serializer" error handling in output plugin (#160) [#160](https://github.com/logstash-plugins/logstash-integration-kafka/pull/160)

## 11.3.3
  - Fix "Can't modify frozen string" error when record value is `nil` (tombstones) [#155](https://github.com/logstash-plugins/logstash-integration-kafka/pull/155)

## 11.3.2
  - Fix: update Avro library [#150](https://github.com/logstash-plugins/logstash-integration-kafka/pull/150)

## 11.3.1
  - Fix: update snappy dependency [#148](https://github.com/logstash-plugins/logstash-integration-kafka/pull/148)

## 11.3.0
  - Bump kafka client to 3.4.1 [#145](https://github.com/logstash-plugins/logstash-integration-kafka/pull/145)

## 11.2.1
 - Fix nil exception to empty headers of record during event metadata assignment [#140](https://github.com/logstash-plugins/logstash-integration-kafka/pull/140)

## 11.2.0
 - Added TLS truststore and keystore settings specifically to access the schema registry [#137](https://github.com/logstash-plugins/logstash-integration-kafka/pull/137)

## 11.1.0
 - Added config `group_instance_id` to use the Kafka's consumer static membership feature [#135](https://github.com/logstash-plugins/logstash-integration-kafka/pull/135)

## 11.0.0
  - Changed Kafka client to 3.3.1, requires Logstash >= 8.3.0. 
  - Deprecated `default` value for setting `client_dns_lookup` forcing to `use_all_dns_ips` when explicitly used [#130](https://github.com/logstash-plugins/logstash-integration-kafka/pull/130)
  - Changed the consumer's poll from using the one that blocks on metadata retrieval to the one that doesn't [#136](https://github.com/logstash-plugins/logstash-integration-kafka/pull/133)

## 10.12.1
  - Fix: update Avro library on 10.x [#149](https://api.github.com/repos/logstash-plugins/logstash-integration-kafka/pulls/149)

## 10.12.0
  - bump kafka client to 2.8.1 [#115](https://github.com/logstash-plugins/logstash-integration-kafka/pull/115)

## 10.11.0
  - Feat: added connections_max_idle_ms setting for output [#118](https://github.com/logstash-plugins/logstash-integration-kafka/pull/118)
  - Refactor: mixins to follow shared mixin module naming

## 10.10.1
  - Update CHANGELOG.md [#114](https://api.github.com/repos/logstash-plugins/logstash-integration-kafka/pulls/114)

## 10.10.0
  - Added config setting to enable 'zstd' compression in the Kafka output [#112](https://github.com/logstash-plugins/logstash-integration-kafka/pull/112)

## 10.9.0
  - Refactor: leverage codec when using schema registry [#106](https://github.com/logstash-plugins/logstash-integration-kafka/pull/106)
    Previously using `schema_registry_url` parsed the payload as JSON even if `codec => 'plain'` was set, this is no longer the case.  

## 10.8.2
  - [DOC] Updates description of `enable_auto_commit=false` to clarify that the commit happens after data is fetched AND written to the queue [#90](https://github.com/logstash-plugins/logstash-integration-kafka/pull/90)
  - Fix: update to Gradle 7 [#104](https://github.com/logstash-plugins/logstash-integration-kafka/pull/104)
  - [DOC] Clarify Kafka client does not support proxy [#103](https://github.com/logstash-plugins/logstash-integration-kafka/pull/103)

## 10.8.1
  - [DOC] Removed a setting recommendation that is no longer applicable for Kafka 2.0+ [#99](https://github.com/logstash-plugins/logstash-integration-kafka/pull/99)

## 10.8.0
  - Added config setting to enable schema registry validation to be skipped when an authentication scheme unsupported
    by the validator is used [#97](https://github.com/logstash-plugins/logstash-integration-kafka/pull/97)

## 10.7.7
  - Fix: Correct the settings to allow basic auth to work properly, either by setting `schema_registry_key/secret` or embedding username/password in the
    url [#94](https://github.com/logstash-plugins/logstash-integration-kafka/pull/94)

## 10.7.6
  - Test: specify development dependency version [#91](https://github.com/logstash-plugins/logstash-integration-kafka/pull/91)

## 10.7.5
  - Improved error handling in the input plugin to avoid errors 'escaping' from the plugin, and crashing the logstash
    process [#87](https://github.com/logstash-plugins/logstash-integration-kafka/pull/87)

## 10.7.4
  - Docs: make sure Kafka clients version is updated in docs [#83](https://github.com/logstash-plugins/logstash-integration-kafka/pull/83)
    Since **10.6.0** Kafka client was updated to **2.5.1**

## 10.7.3
  - Changed `decorate_events` to add also Kafka headers [#78](https://github.com/logstash-plugins/logstash-integration-kafka/pull/78)

## 10.7.2
  - Update Jersey dependency to version 2.33 [#75](https://github.com/logstash-plugins/logstash-integration-kafka/pull/75)

## 10.7.1
  - Fix: dropped usage of SHUTDOWN event deprecated since Logstash 5.0 [#71](https://github.com/logstash-plugins/logstash-integration-kafka/pull/71)
  
## 10.7.0
  - Switched use from Faraday to Manticore as HTTP client library to access Schema Registry service 
    to fix issue [#63](https://github.com/logstash-plugins/logstash-integration-kafka/pull/63) 

## 10.6.0
  - Added functionality to Kafka input to use Avro deserializer in retrieving data from Kafka. The schema is retrieved
    from an instance of Confluent's Schema Registry service [#51](https://github.com/logstash-plugins/logstash-integration-kafka/pull/51)
     
## 10.5.3
  - Fix: set (optional) truststore when endpoint id check disabled [#60](https://github.com/logstash-plugins/logstash-integration-kafka/pull/60).
    Since **10.1.0** disabling server host-name verification (`ssl_endpoint_identification_algorithm => ""`) did not allow 
    the (output) plugin to set `ssl_truststore_location => "..."`.

## 10.5.2
  - Docs: explain group_id in case of multiple inputs [#59](https://github.com/logstash-plugins/logstash-integration-kafka/pull/59)

## 10.5.1
  - [DOC]Replaced plugin_header file with plugin_header-integration file. [#46](https://github.com/logstash-plugins/logstash-integration-kafka/pull/46)
  - [DOC]Update kafka client version across kafka integration docs [#47](https://github.com/logstash-plugins/logstash-integration-kafka/pull/47)
  - [DOC]Replace hard-coded kafka client and doc path version numbers with attributes to simplify doc maintenance [#48](https://github.com/logstash-plugins/logstash-integration-kafka/pull/48)  

## 10.5.0
  - Changed: retry sending messages only for retriable exceptions [#27](https://github.com/logstash-plugins/logstash-integration-kafka/pull/29)

## 10.4.1
  - [DOC] Fixed formatting issues and made minor content edits [#43](https://github.com/logstash-plugins/logstash-integration-kafka/pull/43)

## 10.4.0
 - added the input `isolation_level` to allow fine control of whether to return transactional messages [#44](https://github.com/logstash-plugins/logstash-integration-kafka/pull/44)

## 10.3.0
  - added the input and output `client_dns_lookup` parameter to allow control of how DNS requests are made [#28](https://github.com/logstash-plugins/logstash-integration-kafka/pull/28)

## 10.2.0
  - Changed: config defaults to be aligned with Kafka client defaults [#30](https://github.com/logstash-plugins/logstash-integration-kafka/pull/30)

## 10.1.0
  - updated kafka client (and its dependencies) to version 2.4.1 ([#16](https://github.com/logstash-plugins/logstash-integration-kafka/pull/16))
  - added the input `client_rack` parameter to enable support for follower fetching
  - added the output `partitioner` parameter for tuning partitioning strategy
  - Refactor: normalized error logging a bit - make sure exception type is logged
  - Fix: properly handle empty ssl_endpoint_identification_algorithm [#8](https://github.com/logstash-plugins/logstash-integration-kafka/pull/8)
  - Refactor : made `partition_assignment_strategy` option easier to configure by accepting simple values from an enumerated set instead of requiring lengthy class paths ([#25](https://github.com/logstash-plugins/logstash-integration-kafka/pull/25))

## 10.0.1
  - Fix links in changelog pointing to stand-alone plugin changelogs.
  - Refactor: scope java_import to plugin class

## 10.0.0
  - Initial release of the Kafka Integration Plugin, which combines
    previously-separate Kafka plugins and shared dependencies into a single
    codebase; independent changelogs for previous versions can be found:
     - [Kafka Input Plugin @9.1.0](https://github.com/logstash-plugins/logstash-input-kafka/blob/v9.1.0/CHANGELOG.md)
     - [Kafka Output Plugin @8.1.0](https://github.com/logstash-plugins/logstash-output-kafka/blob/v8.1.0/CHANGELOG.md)
