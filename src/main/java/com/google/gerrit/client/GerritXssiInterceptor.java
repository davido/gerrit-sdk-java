// Copyright (C) 2026 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.google.gerrit.client;

import java.io.IOException;
import okhttp3.Interceptor;
import okhttp3.MediaType;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * OkHttp {@link Interceptor} that strips Gerrit's {@code )]}'} XSSI guard from JSON response bodies
 * before the generated client parses them.
 *
 * <p>Every Gerrit JSON body starts with {@code )]}'} on its own line, to defeat cross-site script
 * inclusion. That prefix is not valid JSON and is not expressible in OpenAPI, so the generated
 * client cannot know about it. Unlike the Rust SDK (whose blocking reqwest has no hook),
 * okhttp-gson exposes an interceptor -- so this strips the guard with no edit to generated code.
 * This class is hand-written and lives alongside the generated invoker classes; {@code generate.sh}
 * copies it back in after each regeneration.
 */
public final class GerritXssiInterceptor implements Interceptor {
  private static final String GUARD = ")]}'\n";

  /** A ready-to-use {@link ApiClient} for {@code basePath} with the interceptor installed. */
  public static ApiClient newClient(String basePath) {
    ApiClient client = new ApiClient();
    client.setBasePath(basePath);
    client.setHttpClient(
        client.getHttpClient().newBuilder().addInterceptor(new GerritXssiInterceptor()).build());
    return client;
  }

  /** Strip the leading {@code )]}'} guard from a string (exposed for unit testing). */
  public static String strip(String body) {
    return body.startsWith(GUARD) ? body.substring(GUARD.length()) : body;
  }

  @Override
  public Response intercept(Chain chain) throws IOException {
    Response response = chain.proceed(chain.request());
    ResponseBody body = response.body();
    if (body == null) {
      return response;
    }
    MediaType contentType = body.contentType();
    if (contentType == null || !"json".equalsIgnoreCase(contentType.subtype())) {
      return response; // leave text/plain and binary responses untouched
    }
    String stripped = strip(body.string());
    return response.newBuilder().body(ResponseBody.create(stripped, contentType)).build();
  }
}
