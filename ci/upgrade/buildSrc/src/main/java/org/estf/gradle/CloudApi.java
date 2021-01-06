package org.estf.gradle;

import co.elastic.cloud.api.client.generated.DeploymentsApi;
import co.elastic.cloud.api.model.generated.ApmInfo;
import co.elastic.cloud.api.model.generated.ElasticsearchClusterInfo;
import co.elastic.cloud.api.model.generated.EnterpriseSearchInfo;
import co.elastic.cloud.api.model.generated.KibanaClusterInfo;
import co.elastic.cloud.api.util.Waiter;
import com.bettercloud.vault.VaultException;
import io.swagger.client.ApiClient;

import java.io.IOException;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.ArrayList;

/**
 * CloudApi
 *
 * @author  Liza Dayoub
 *
 */
public class CloudApi {

    private String host = "public-api.staging.foundit.no";
    final private ApiClient apiClient;
    final private String esRefId = "main-elasticsearch";
    final private String kbRefId = "main-kibana";
    final private String apmRefId = "main-apm";
    final private String ensRefId = "main-enterprise_search";

    CloudApi() throws VaultException, IOException {
        VaultCredentials credentials = new VaultCredentials();

        String estf_host = System.getenv("ESTF_CLOUD_HOST");
        if (estf_host != null) {
            host = estf_host;
        }
        String url = getUrl();

        System.out.println("Debug: Setting up API client");
        apiClient = new ApiClient();
        apiClient.setApiKey(credentials.getApiKey());
        apiClient.setApiKeyPrefix("ApiKey");
        apiClient.setBasePath(url);
        apiClient.setDebugging(true);
        System.out.println("Debug: API URL: " + url);
    }

    public ApiClient getApiClient() {
        return apiClient;
    }

    public String getEsRefId() {
        return esRefId;
    }

    public String getKbRefId() {
        return kbRefId;
    }

    public String getEnsRefId() {
        return ensRefId;
    }

    public String getApmRefId() {
        return apmRefId;
    }

    public boolean isElasticsearchClusterRunning(ElasticsearchClusterInfo elasticsearchClusterInfo) {
        return ElasticsearchClusterInfo.StatusEnum.STARTED.equals(elasticsearchClusterInfo.getStatus());
    }

    public boolean isKibanaClusterRunning(KibanaClusterInfo kibanaClusterInfo) {
        return KibanaClusterInfo.StatusEnum.STARTED.equals(kibanaClusterInfo.getStatus());
    }

    public boolean isApmRunning(ApmInfo apmInfo) {
        return ApmInfo.StatusEnum.STARTED.equals(apmInfo.getStatus());
    }

    public boolean isEnterpriseSearchRunning(EnterpriseSearchInfo enterpriseSearchInfo) {
        return EnterpriseSearchInfo.StatusEnum.STARTED.equals(enterpriseSearchInfo.getStatus());
    }

    public void waitForElasticsearch(DeploymentsApi deploymentsApi, String deploymentId) {
        Waiter.waitFor(() -> this.isElasticsearchClusterRunning(
                deploymentsApi.getDeploymentEsResourceInfo(
                        deploymentId,
                        this.esRefId,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false,
                        0,
                        false,
                        false).getInfo()));
    }

    public void waitForKibana(DeploymentsApi deploymentsApi, String deploymentId) {
        Waiter.waitFor(() -> this.isKibanaClusterRunning(
                deploymentsApi.getDeploymentKibResourceInfo(
                        deploymentId,
                        this.kbRefId,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false).getInfo()
        ));
    }

    public void waitForApm(DeploymentsApi deploymentsApi, String deploymentId) {
        Waiter.waitFor(() -> this.isApmRunning(
                deploymentsApi.getDeploymentApmResourceInfo(
                        deploymentId,
                        this.apmRefId,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false).getInfo()
        ));
    }

    public void waitForEnterpriseSearch(DeploymentsApi deploymentsApi, String deploymentId) {
        Waiter.waitFor(() -> this.isEnterpriseSearchRunning(
                deploymentsApi.getDeploymentEnterpriseSearchResourceInfo(
                        deploymentId,
                        this.ensRefId,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false).getInfo()
        ));
    }

    public String getEnvRegion() {
        String default_region = "us-east-1";
        ArrayList<String> regions = new ArrayList<>();
        regions.add("us-east-1");
        regions.add("us-west-1");
        regions.add("eu-west-1");
        regions.add("ap-southeast-1");
        regions.add("ap-northeast-1");
        regions.add("sa-east-1");
        regions.add("ap-southeast-2");
        regions.add("aws-eu-central-1");
        regions.add("gcp-us-central1");
        regions.add("gcp-europe-west-1");
        regions.add("azure-eastus2");

        String data_region = System.getenv("ESTF_CLOUD_REGION");
        if (data_region == null) {
            return default_region;
        }

        if (regions.contains(data_region)) {
            return data_region;
        }
        return default_region;
    }

    private String getHost() {
        try {
            if (host.contains("http")) {
                URL url = new URL(host);
                return url.getHost();
            }
        } catch (MalformedURLException e) {
            throw new Error(e.toString());
        }
        return host;
    }

    private String getUrl() {
        return "https://" + getHost() + "/api/v1";
    }
}
