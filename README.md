# gerrit-sdk-java

A **generated Java SDK** for the Gerrit Code Review REST API (the `gerrit-sdk-java`
Maven artifact), produced from Gerrit's statically generated **OpenAPI 3.1** document. No
hand-written request/response types: every operation and model comes from the spec, so
the client never drifts from the server.

## The pipeline (end to end)

```
  gerrit                      gerrit-sdk-java                gerrit-sdk-java-client
  (emit the spec)      -->    (this repo: the SDK)    -->    (Bazel consumer)
  parse-only OpenAPI          openapi-generator (java,       rules_jvm_external
  emitter                     okhttp-gson) + XSSI interceptor  <- JitPack
```

1. **Gerrit emits the spec** — a parse-only emitter reads the server's REST bindings via
   the javac Compiler Tree API (no running server, no reflection) and writes an OpenAPI
   3.1 JSON.
2. **This repo pins that spec** (`rest-api-openapi.json`).
3. **`generate.sh` generates the SDK** — openapi-generator (java, `okhttp-gson`) into
   `src/main/java`.
4. **A consumer reuses it via JitPack** — see [Consume it](#consume-it). The worked
   example (get-change-detail, colored) lives in the separate Bazel repo
   `gerrit-sdk-java-client`.

Demonstrates feasibility for Gerrit issue
[40011133](https://issues.gerritcodereview.com/issues/40011133).

## Versions

- **Java 21** (source/target, Gerrit's own language level), built by openapi-generator's `okhttp-gson` client.
- **OkHttp 5.0.0**, **Gson 2.14.0**, **maven-compiler-plugin 3.13.0** — bumped off the
  generator's stale defaults (Java 1.8 / okhttp 4.12 / gson 2.10.1); the generated code
  compiles clean on the latest.
- Maven coordinates: **`com.github.davido:gerrit-sdk-java:3.15.0-SNAPSHOT`** — the git
  tag mirrors the Gerrit version.

## What's in this repo

- `src/main/java/com/google/gerrit/client/**` — the generated client: **325 operations**
  across **7 API classes** (`api/`) and **275 models** (`model/`), over OkHttp + Gson.
- `GerritXssiInterceptor.java` — a hand-written OkHttp `Interceptor` that strips Gerrit's
  `)]}'` XSSI guard (the one Gerrit-specific step; see below). `generate.sh` copies it
  into the invoker package after each regeneration.
- `pom.xml` — **Maven only, no Gradle** (JitPack builds this repo with the Maven
  toolchain).
- `jitpack.yml`, `generate.sh`, `rest-api-openapi.json`.

## Regenerate

```bash
./generate.sh [path-or-url]      # default: ./rest-api-openapi.json
```

## The Gerrit-specific handling

The spec is consumed as-is, and **no generated code is patched**:

- **XSSI guard** — every Gerrit JSON body starts with `)]}'` on its own line, which is not
  valid JSON and not expressible in OpenAPI. `GerritXssiInterceptor` (an OkHttp
  `Interceptor`) strips it; build a client with it via
  `GerritXssiInterceptor.newClient(basePath)`. (okhttp-gson exposes interceptors, so no
  source edit is needed — unlike the Rust SDK's blocking reqwest.)

The case-colliding `O`/`o` query params and the enums are handled correctly by the
generator on its own — no query patch (unlike Rust) and no enum flag (unlike Go).

## Build

```bash
mvn -DskipTests package     # requires JDK 21
```

## Consume it

### Via JitPack (Maven / Gradle / Bazel)

JitPack builds the git tag into a Maven artifact **on demand** — nothing is uploaded.
The first request for the coordinate triggers a build (`./mvnw clean install`) that
JitPack then caches. `jitpack.yml` pins `openjdk21`, which JitPack ships out of the box.

> **JitPack requires a Maven (or Gradle) toolchain** to build the artifact — hence this
> repo ships a `pom.xml` (not Bazel). ;-) It also ships a **Maven wrapper** (`mvnw`,
> pinned to Maven 3.9.9): JitPack runs `./mvnw`, and without it JitPack falls back to a
> prehistoric Maven 3.0 that fetches over `http://` and fails.

**Triggering / warming the build.** The first fetch builds it, but you can warm the cache
(and watch it build) by requesting any artifact URL, or via the JitPack UI:

```bash
# trigger + tail the build log
curl -s https://jitpack.io/com/github/davido/gerrit-sdk-java/v3.15.0-SNAPSHOT/build.log
# or just fetch the pom (triggers the build, then serves it once green)
curl -s https://jitpack.io/com/github/davido/gerrit-sdk-java/v3.15.0-SNAPSHOT/gerrit-sdk-java-v3.15.0-SNAPSHOT.pom
```
Or open `https://jitpack.io/#davido/gerrit-sdk-java` and click the tag under *Releases*.
The first build takes a couple of minutes; afterwards it's cached and instant.

Maven:
```xml
<repositories>
  <repository><id>jitpack.io</id><url>https://jitpack.io</url></repository>
</repositories>
<dependency>
  <groupId>com.github.davido</groupId>
  <artifactId>gerrit-sdk-java</artifactId>
  <version>v3.15.0-SNAPSHOT</version>
</dependency>
```

Bazel (`rules_jvm_external`):
```python
maven.install(
    artifacts = ["com.github.davido:gerrit-sdk-java:v3.15.0-SNAPSHOT"],
    repositories = ["https://jitpack.io", "https://repo1.maven.org/maven2"],
)
```

A full Bazel consumer (get-change-detail) lives in **`gerrit-sdk-java-client`**.

```java
import com.google.gerrit.client.GerritXssiInterceptor;
import com.google.gerrit.client.api.ChangesApi;

var api = new ChangesApi(GerritXssiInterceptor.newClient("https://gerrit-review.googlesource.com"));
var change = api.getChangesChangeId("621763", null, null, java.util.List.of("LABELS"));
System.out.println(change.getSubject());
```

### Future: a Google Cloud Storage Maven bucket

As an alternative to JitPack, the artifact could be `mvn deploy`ed to a **GCS-backed
Maven repository** — the same pattern Gerrit uses for its own build deps (e.g.
`blame-cache` and friends on the `gerrit-maven` bucket) — and consumed via
`rules_jvm_external` pointing at that bucket. No JitPack dependency, at the cost of a
deploy step and bucket access.

## License

Apache 2.0. See [LICENSE.txt](LICENSE.txt).
