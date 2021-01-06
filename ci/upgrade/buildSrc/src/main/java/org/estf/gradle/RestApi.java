package org.estf.gradle;

import org.apache.http.HttpHeaders;
import org.apache.http.HttpResponse;
import org.apache.http.client.HttpClient;
import org.apache.http.client.methods.HttpDelete;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.client.methods.HttpPut;
import org.apache.http.entity.ContentType;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.HttpClientBuilder;

import java.io.IOException;
import java.util.Base64;

/**
 * RestApi
 *
 * @author  Liza Dayoub
 *
 */
public class RestApi {

    private String basicAuthPayload;
    private final String username;
    private final String password;
    private final String version;
    private final String upgradeVersion;
    private int majorVersion;
    private int majorUpgradeVersion;

    public RestApi(String username, String password, String version, String upgradeVersion) {
        this.username = username;
        this.password = password;
        this.version = version;
        this.upgradeVersion = upgradeVersion;
        setCredentials();
    }

    public HttpResponse post(String path, String jsonStr, Boolean postToKbn) throws IOException {
        HttpPost postRequest = new HttpPost(path);
        postRequest.setHeader(HttpHeaders.AUTHORIZATION, basicAuthPayload);
        if (postToKbn) {
            postRequest.setHeader("kbn-xsrf", "automation");
        }
        System.out.println("** POST REQUEST **");
        System.out.println("Path: " + path);
        System.out.println("Payload: " + jsonStr);
        postRequest.setHeader(HttpHeaders.CONTENT_TYPE, "application/json");
        StringEntity entity = new StringEntity(jsonStr);
        entity.setContentType(ContentType.APPLICATION_JSON.getMimeType());
        postRequest.setEntity(entity);
        HttpClient client = HttpClientBuilder.create().build();
        HttpResponse response = client.execute(postRequest);
        int statusCode = response.getStatusLine().getStatusCode();
        if (statusCode != 200) {
            throw new IOException("FAILED! POST: " + response.getStatusLine() + " " + path);
        }
        return response;
    }

    public HttpResponse put(String path, String jsonStr, Boolean postToKbn) throws IOException {
        HttpPut putRequest = new HttpPut(path);
        putRequest.setHeader(HttpHeaders.AUTHORIZATION, basicAuthPayload);
        if (postToKbn) {
            putRequest.setHeader("kbn-xsrf", "automation");
        }
        System.out.println("** PUT REQUEST **");
        System.out.println("Path: " + path);
        System.out.println("Payload: " + jsonStr);
        putRequest.setHeader(HttpHeaders.CONTENT_TYPE, "application/json");
        StringEntity entity = new StringEntity(jsonStr);
        entity.setContentType(ContentType.APPLICATION_JSON.getMimeType());
        putRequest.setEntity(entity);
        HttpClient client = HttpClientBuilder.create().build();
        HttpResponse response = client.execute(putRequest);
        int statusCode = response.getStatusLine().getStatusCode();
        if (statusCode != 200) {
            throw new IOException("FAILED! PUT: " + response.getStatusLine() + " " + path);
        }
        return response;
    }

    public HttpResponse get(String path) throws IOException {
        HttpGet getRequest = new HttpGet(path);
        getRequest.setHeader(HttpHeaders.AUTHORIZATION, basicAuthPayload);
        getRequest.setHeader(HttpHeaders.CONTENT_TYPE, "application/json");
        System.out.println("** GET REQUEST **");
        System.out.println("Path: " + path);
        HttpClient client = HttpClientBuilder.create().build();
        HttpResponse response = client.execute(getRequest);
        int statusCode = response.getStatusLine().getStatusCode();
        if (statusCode != 200) {
            throw new IOException("FAILED! GET: " + response.getStatusLine() + " " + path);
        }
        return response;
    }

    public HttpResponse delete(String path, Boolean postToKbn) throws IOException {
        HttpDelete deleteRequest = new HttpDelete(path);
        deleteRequest.setHeader(HttpHeaders.AUTHORIZATION, basicAuthPayload);
        if (postToKbn) {
            deleteRequest.setHeader("kbn-xsrf", "automation");
        }
        deleteRequest.setHeader(HttpHeaders.CONTENT_TYPE, "application/json");
        System.out.println("** DELETE REQUEST **");
        System.out.println("Path: " + path);
        HttpClient client = HttpClientBuilder.create().build();
        HttpResponse response = client.execute(deleteRequest);
        int statusCode = response.getStatusLine().getStatusCode();
        if (statusCode != 200) {
            throw new IOException("FAILED! DELETE: " + response.getStatusLine() + " " + path);
        }
        return response;
    }

    private int parseMajorVersion(String version) {
        int dotInd = version.indexOf(".");
        int ret_version;
        if (dotInd != -1) {
            ret_version = Integer.parseInt(version.substring(0,dotInd));
        } else {
            ret_version = Integer.parseInt(version);
        }
        return ret_version;
    }

    public int setMajorVersion() {
        majorVersion = parseMajorVersion(version);
        return majorVersion;
    }

    public int getMajorVersion() {
        return majorVersion;
    }

    public int setMajorUpgradeVersion() {
        majorUpgradeVersion = parseMajorVersion(upgradeVersion);
        return majorUpgradeVersion;
    }

    public int getUpgradeMajorVersion() {
        return majorUpgradeVersion;
    }

    private void setCredentials() {
        String credentials = username + ":" + password;
        this.basicAuthPayload = "Basic " + Base64.getEncoder().encodeToString(credentials.getBytes());
    }
}
