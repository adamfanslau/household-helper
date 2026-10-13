package com.householdhelper.app.data

import android.util.Log
import com.householdhelper.app.BuildConfig
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.auth.Auth
import io.ktor.client.plugins.auth.providers.BearerTokens
import io.ktor.client.plugins.auth.providers.bearer
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json

/**
 * Ktor + OkHttp client for hh-api. The bearer provider loads a cached Firebase token and refreshes
 * it once on a 401; a second 401 surfaces as ApiException(401), which the repositories map to sign-out.
 */
class ApiClient(private val auth: AuthRepository, baseUrl: String = BuildConfig.API_BASE_URL) {
    val http: HttpClient = HttpClient(OkHttp) {
        expectSuccess = false
        install(ContentNegotiation) { json(HHJson) }
        install(Auth) {
            bearer {
                loadTokens { BearerTokens(auth.idToken(false), "") }
                refreshTokens { BearerTokens(auth.idToken(true), "") }
                sendWithoutRequest { true }
            }
        }
        defaultRequest {
            url(baseUrl)
            contentType(ContentType.Application.Json)
        }
    }

    suspend inline fun <reified T> get(path: String): T = call(HttpMethod.Get, path).body()
    suspend inline fun <reified T, reified B> post(path: String, body: B): T = call(HttpMethod.Post, path) { setBody(body) }.body()
    suspend inline fun <reified T> post(path: String): T = call(HttpMethod.Post, path).body()
    suspend inline fun <reified T, reified B> patch(path: String, body: B): T = call(HttpMethod.Patch, path) { setBody(body) }.body()
    suspend fun delete(path: String) { call(HttpMethod.Delete, path) }

    suspend fun call(method: HttpMethod, path: String, block: HttpRequestBuilder.() -> Unit = {}): HttpResponse {
        val res = http.request(path) {
            this.method = method
            block()
        }
        if (res.status.value in 200..299) return res
        val text = res.bodyAsText()
        val parsed = runCatching { HHJson.decodeFromString(ApiErrorBody.serializer(), text) }.getOrNull()
        Log.w(AuthRepository.TAG, "api ${method.value} $path -> ${res.status.value} ${parsed?.error?.code ?: ""}")
        throw ApiException(res.status.value, parsed?.error?.code ?: "http_${res.status.value}", parsed?.error?.message ?: res.status.description)
    }
}
