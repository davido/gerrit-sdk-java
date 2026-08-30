#!/usr/bin/env bash
# Regenerate the Gerrit Java SDK from the OpenAPI document.
#
#   openapi-generator (java, okhttp-gson)  ->  no source patching
#
# No generated-code patches: the one Gerrit-specific concern (the )]}' XSSI guard) is
# handled by the hand-written GerritXssiInterceptor (an OkHttp Interceptor), not by
# editing output. The generator also maps the case-colliding query params O (scalar) /
# o (array) to distinct params on its own, so unlike the Rust SDK there is no query patch.
#
# Maven only (no Gradle): JitPack builds this repo's tag with the Maven toolchain.
#
# Usage: ./generate.sh [path-or-url]   (default: ./rest-api-openapi.json)
set -euo pipefail
cd "$(dirname "$0")"
SPEC="${1:-rest-api-openapi.json}"

if [[ "$SPEC" == http://* || "$SPEC" == https://* ]]; then
  echo "0/4 fetch spec from $SPEC"
  curl -fsSL "$SPEC" -o rest-api-openapi.json
  SPEC=rest-api-openapi.json
fi

VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["info"]["version"])' "$SPEC")

echo "1/4 clean generated sources"
rm -rf src docs

echo "2/4 generate java client (okhttp-gson, Gerrit $VERSION)"
# README.md / LICENSE.txt / GerritXssiInterceptor / gradle files are handled by
# .openapi-generator-ignore; pom.xml is regenerated with the version below.
npx --yes @openapitools/openapi-generator-cli@2.41.0 generate \
  -g java -i "$SPEC" -o . \
  --additional-properties=library=okhttp-gson,hideGenerationTimestamp=true,groupId=com.github.davido,artifactId=gerrit-sdk-java,artifactVersion="$VERSION",apiPackage=com.google.gerrit.client.api,modelPackage=com.google.gerrit.client.model,invokerPackage=com.google.gerrit.client \
  >/dev/null

echo "3/4 restore hand-written XSSI interceptor + modernize the pom"
cp GerritXssiInterceptor.java src/main/java/com/google/gerrit/client/GerritXssiInterceptor.java
# The generator's defaults are stale (Java 1.8, okhttp 4.12, gson 2.10.1, compiler
# plugin 3.8.1); the generated code compiles clean on the latest, so bump. (python, not
# sed -i, for macOS/GNU portability.)
python3 - <<'PY'
p = "pom.xml"; s = open(p).read()
s = s.replace("<java.version>1.8</java.version>", "<java.version>21</java.version>")
s = s.replace("<version>3.8.1</version>", "<version>3.13.0</version>")  # maven-compiler-plugin
s = s.replace("<okhttp-version>4.12.0</okhttp-version>", "<okhttp-version>5.4.0</okhttp-version>")
s = s.replace("<gson-version>2.10.1</gson-version>", "<gson-version>2.14.0</gson-version>")
# The java generator stamps OpenAPI-Generator's own project/SCM/license metadata into
# the pom regardless of the spec; rewrite it to this repo + Apache-2.0.
s = s.replace("https://github.com/openapitools/openapi-generator", "https://github.com/davido/gerrit-sdk-java")
s = s.replace("scm:git:git@github.com:openapitools/openapi-generator.git", "scm:git:git@github.com:davido/gerrit-sdk-java.git")
s = s.replace("<name>Unlicense</name>", "<name>Apache-2.0</name>")
s = s.replace("<description>OpenAPI Java</description>", "<description>Generated Java SDK for the Gerrit Code Review REST API</description>")
open(p, "w").write(s)
PY

echo "4/4 drop non-Maven scaffolding (no Gradle)"
rm -rf build.gradle build.sbt settings.gradle gradle gradlew gradlew.bat gradle.properties git_push.sh docs api .travis.yml

echo "done: src/ regenerated from $SPEC; XSSI via GerritXssiInterceptor; Maven-only; okhttp 5.4 / gson 2.14, pom metadata=Apache-2.0"
