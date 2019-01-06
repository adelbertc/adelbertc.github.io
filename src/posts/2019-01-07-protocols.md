---
title: Stop speaking gibberish, start using interfaces
---

In the age of modular microservices, data pipelines, serverless, and IoT, handling data serialization has become a major
design decision. While monolithic architectures are well, monolithic, coordination between components is simply a
function call away. In contrast, components that are separated by a network or run as different stages in a workflow
must communicate by serializing and deserializing data. Add in questions like how much data is being serialized,
how often it needs to be serialized, how many languages are in play, and how various components evolve, and we can see
how data serialization has turned from an incidental problem to a central one.

One approach to this problem is to use language-native serialization like [Java serialization][javaSerialization]
or [Python pickling][pickle]. So long as we are using the same language, this has the benefit of being convenient
and easy to use. It is common to see systems like [Apache Spark][spark] rely heavily on native serialization to handle
communication within the system. However once we need to consider other factors like using multiple languages or
evolving the serialization scheme, such mechanisms are quickly ruled out.

Another approach that much of the industry has converged on is to use [JSON][json]. JSON is human readable, relatively
simple, language agnostic, and widespread enough that most languages have a JSON library (some even in the standard
library). For these reasons a vast amount of public APIs and microservices today have adopted JSON as their main data
format. However JSON suffers from a big problem (as does language-native serialization): it is unchecked.

When a client sends a request to or receives a response from a server, it needs to serialize or deserialize the
corresponding payload. Writing these (de)serializers often involves staring at API documentation, hoping it isn't
out of date or that you don't make a mistake.

> A note on automatic derivation: Some languages like [Haskell][haskell] and [Rust][rust] provide a way to automatically
> derive a (de)serializer from a data type. This is often a dangerous practice in a production setting, especially
> if the data type being derived from is used in the business logic itself. Innocent refactorings or changes to
> a data type silently change the serialization scheme with no way of communicating that change to clients.
> Anecdotally myself and several people I know have been bitten by the consequences of this. Even in the rare situation
> where everyone is using the same language and uses a shared library to communicate, there is still a versioning
> and compatibility question to be answered, as we will see in the next section. The only time I reach for
> automatic derivation is during prototyping or if the message flows only through the same component and is not
> persisted anywhere.

In addition, interfaces inevitably evolve over time. Questions around backwards and forwards compatibility are
inevitable, as are questions around handling breaking API changes. Data serialization is intrinsically tied to this
as how the data is serialized affects whether or not readers with older or newer schemas can read the data at all.
Consider a record containing a string and an integer, serialized one after another with the string
prefixed by its length. Consumers write a parser for this accordingly. The producer later on adds another
length-prefixed string to the record. How does the producer signal this change? How does the consumer account for
this change? Is the consumer even aware of this change? Does it need to be?

This brings us to interface definition languages, or IDLs. IDLs are a domain-specific language for describing data
types from which serializers and deserializers for various languages can be generated. For example, in
[Avro][avro] a Person record with a name and age field would be defined like..

```json
{
  "type": "record",
  "name": "Person",
  "fields": [
    { "name": "name", "type": "string" },
    { "name": "age", "type": "int" }
  ]
}
```

..and given that definition, an Avro library would generate (de)serialization code that could be used
by either the server and the client. This way the source of truth for the interface is centralized in a
language-agnostic format and serialization logic is handled solely by general purpose, mechanized tooling.

Besides providing a data serialization format for the specified data type, one of the most important features an IDL
provides is schema evolution. IDLs provide a set of rules around what forwards or backwards compatible changes can
be made to a definition and sometimes provide an automated checker for those rules. This allows for cases where say,
a producer adds a field to a record but the consumer (perhaps using an older version of the
definition) wants to ignore it and continue parsing as before.

Over the past several years many IDLs have popped up from Google's [Protocol Buffers][protobuf] to [OpenAPI][openApi]
to [extprot][extprot] to [Cap'n Proto][capnProto]. The design space is huge and different IDLs are crafted in
different environments optimized for different use cases with different tradeoffs. Instead of attempting to enumerate
a select few IDLs let's instead take a look at some axes we can use to evaluate them.

**Schema evolution** Arguably the most important feature of an IDL is how schema evolution is handled. Protocol Buffers
use a [set of rules][protobufRules] that are consequences of how it serializes data, like how an optional field can
be changed to a repeated field. Avro has the notion of a writer's schema and a reader's schema and undergoes a
process called [schema resolution][avroRules] to figure out how to parse a record (with enough handwaving and squinting
schema resolution resembles record subtyping). Martin Kleppmann has a [good article][kleppmannArticle] comparing
schema evolution rules of Protocol Buffers, Avro, and Thrift on his blog, plus a more extensive version of it
in his fantastic book [Designing Data-Intensive Applications][dataIntensive].

**Compactness** Different IDLs will serialize data differently, with some IDLs providing multiple serialization backends
(Avro has a binary and JSON encoding). Some IDLs like [JSON Schema][jsonSchema] serialize to JSON which while human
readable, is inherently bulky. Protocol Buffers encodes each field prefixed by its tag and type, one after another.
Avro's binary serialization contains no field identifying information at all in the encoding, pushing that logic
completely into the parser itself which requires the writer's schema to be on hand.

**Performance** If you're sending JSON or using RPC to call across a web of microservices or constantly reading and
writing data in a data-intensive setting, how fast (de)serialization happens matters a lot. Protocol Buffers and Apache
Thrift were designed for RPC and perform relatively efficiently. Cap'n Proto was designed from the ground-up to be
extremely efficient to (de)serialize and comes with support for things like memory-mapped files.

**Type system** Because IDLs are essentially languages to describe data-types, the type system of the IDL is also
important. Most IDLs support the basic few people expect such as integers, booleans, and strings. Once we consider
sum types or union types though, things begin to fall apart. Protocol Buffers calls sum types "Oneof", but they
are not first-class as they [cannot be repeated][protobufSum]. Thrift has unions but because of implementation
details they are [always considered optional fields][thriftSum]. Avro has [good support for (anonymous) unions][avroSum]
in theory but in practice the ecosystem has some catching up to do
([1](https://issues.apache.org/jira/browse/AVRO-2140), [2](https://issues.apache.org/jira/browse/AVRO-1343),
[3](https://github.com/confluentinc/schema-registry/issues/253)). Extprot, having come from an OCaml setting, seems
to have very good support for unions, and a type system familiar to functional programmers.

**Incremental parsing, skipping, streaming** Being able to parse streams of data incrementally and easily skip fields
without parsing them first becomes very important in data-intensive systems. Avro was created in a Hadoop setting and
was therefore designed to support streaming and skipping. Most binary IDLs by virtue of being binary already have
some way of delimiting fields which can be used to skip around. Delimiting records themselves can be a bit trickier
depending on the IDL, but usually doable. Since Avro requires the writer's schema to be on-hand during deserialization,
records can be skipped by skipping each field at a time. Another way as suggested by the
[Protocol Buffers documentation][protobufIncremental] is to roll your own (de)serialization scheme and prefix each
record with its length.

**Ecosystem** While in theory the ecosystem and tooling around one IDL can largely be replicated for any other IDL,
in practice we don't always want to or have the resources to, especially with deadlines looming. Extprot could be a
very nice IDL to use, but it has a significantly smaller ecosystem than Protocol Buffers or Avro. Protocol
Buffers, coming from Google, have lots of momentum behind it thanks to its use in the increasingly
popular [gRPC][grpc]. Thrift is used by [Facebook][thriftFb] and [Twitter][thriftTwitter] and is often integrated
into a lot of their open-source projects, with Twitter's [Finagle][finagle] being a prime example of this. Avro
sees much use in the data processing space, and so readily integrates with systems like [Kafka][avroSr],
[Spark][avroSpark], [Hive][avroHive], and [MapReduce][avroMr].

We are in an age where data is constantly being serialized and deserialized, be it across the network or to and
from disk. How data is serialized and how that serialization scheme is communicated between components has become
a central design decision and should be treated with the appropriate amount of care.

[avro]: https://avro.apache.org/
[avroHive]: https://cwiki.apache.org/confluence/display/Hive/AvroSerDe
[avroMr]: https://avro.apache.org/docs/current/mr.html
[avroRules]: https://avro.apache.org/docs/current/spec.html#Schema+Resolution
[avroSpark]: https://databricks.com/blog/2018/11/30/apache-avro-as-a-built-in-data-source-in-apache-spark-2-4.html
[avroSr]: https://docs.confluent.io/current/schema-registry/docs/index.html
[avroSum]: https://avro.apache.org/docs/current/spec.html#Unions
[capnProto]: https://capnproto.org/
[dataIntensive]: http://dataintensive.net/
[extprot]: https://github.com/mfp/extprot
[finagle]: https://twitter.github.io/finagle/guide/index.html
[grpc]: https://grpc.io/
[haskell]: https://www.haskell.org/
[javaSerialization]: https://docs.oracle.com/javase/tutorial/jndi/objects/serial.html<Paste>
[json]: https://json.org/
[jsonSchema]: https://json-schema.org/
[k8s]: https://kubernetes.io/
[kleppmannArticle]: https://martin.kleppmann.com/2012/12/05/schema-evolution-in-avro-protocol-buffers-thrift.html
[openApi]: https://swagger.io/specification/
[pickle]: https://docs.python.org/3/library/pickle.html
[protobuf]: https://developers.google.com/protocol-buffers/
[protobufEncoding]: https://developers.google.com/protocol-buffers/docs/proto3#scalar
[protobufIncremental]: https://developers.google.com/protocol-buffers/docs/techniques
[protobufRules]: https://developers.google.com/protocol-buffers/docs/proto3#updating<Paste>
[protobufSum]: https://developers.google.com/protocol-buffers/docs/proto3#oneof
[rust]: https://www.rust-lang.org/
[thriftFb]: https://github.com/facebook/fbthrift
[thriftSum]: https://thrift.apache.org/docs/idl#union
[thriftTwitter]: https://github.com/twitter/scrooge
[spark]: https://spark.apache.org/
