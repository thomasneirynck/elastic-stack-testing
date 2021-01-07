package org.estf.gradle;

import co.elastic.cloud.api.client.generated.DeploymentsApi;
import co.elastic.cloud.api.model.generated.*;
import co.elastic.cloud.api.util.Waiter;
import com.bettercloud.vault.VaultException;
import io.swagger.client.ApiClient;

import org.gradle.api.DefaultTask;
import org.gradle.api.tasks.Input;
import org.gradle.api.tasks.TaskAction;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.time.Duration;
import java.util.*;

/**
 * CreateEssDeployment
 *
 * @author  Liza Dayoub
 *
 */
public class CreateEssDeployment extends DefaultTask {

    @Input
    public String stackVersion;

    @Input
    public String elasticsearchUserSettings;

    @Input
    public String kibanaUserSettings;

    @Input
    public boolean mlNode = false;

    @Input
    public boolean ingestNode = false;

    @Input
    public boolean apmNode = false;

    @Input
    public boolean enterpriseSearchNode = false;

    private String deploymentId;
    private String elasticsearchClusterId;
    private String kibanaClusterId;
    private String propertiesFile;

    private String dataRegion;
    private String esInstanceCfg;
    private String kbnInstanceCfg;
    private String mlInstanceCfg;
    private String ingestInstanceCfg;
    private String apmInstanceCfg;
    private String enterpriseSearchInstanceCfg;

    @TaskAction
    public void run() throws IOException, VaultException {
        if (stackVersion == null) {
            throw new Error(this.getClass().getSimpleName() + ": stackVersion is required input");
        }

        CloudApi cloudApi = new CloudApi();
        ApiClient apiClient = cloudApi.getApiClient();
        setInstanceConfiguration(cloudApi);
        DeploymentsApi deploymentsApi = new DeploymentsApi(apiClient);
        DeploymentCreateResponse response = createDeployment(cloudApi, deploymentsApi);
        generatePropertiesFile(response);
    }

    public String getDeploymentId() {
        return deploymentId;
    }

    public String getElasticsearchClusterId() {
        return elasticsearchClusterId;
    }

    public String getKibanaClusterId() {
        return kibanaClusterId;
    }

    public String getPropertiesFile() {
        return propertiesFile;
    }

    private void setInstanceConfiguration(CloudApi cloudApi) {
        esInstanceCfg = "aws.data.highio.i3";
        kbnInstanceCfg = "aws.kibana.r5d";
        mlInstanceCfg = "aws.ml.m5";
        ingestInstanceCfg = "aws.coordinating.m5";
        apmInstanceCfg = "aws.apm.r5d";
        enterpriseSearchInstanceCfg = "aws.enterprisesearch.m5d";
        dataRegion = cloudApi.getEnvRegion();
        if (dataRegion != null) {
            if (dataRegion.contains("gcp")) {
                esInstanceCfg = "gcp.data.highio.1";
                kbnInstanceCfg = "gcp.kibana.1";
                mlInstanceCfg = "gcp.ml.1";
                ingestInstanceCfg = "gcp.coordinating.1";
                apmInstanceCfg = "gcp.apm.1";
                enterpriseSearchInstanceCfg = "gcp.enterprisesearch.1d";
            } else if (dataRegion.contains("azure")) {
                esInstanceCfg = "azure.data.highio.l32sv23";
                kbnInstanceCfg = "azure.kibana.e32sv3";
                mlInstanceCfg = "azure.ml.d64sv3";
                ingestInstanceCfg = "azure.coordinating.d64sv3";
                apmInstanceCfg = "azure.apm.e32sv3";
                enterpriseSearchInstanceCfg = "azure.enterprisesearch.d64sv3";
            }
        }
    }

    private void generatePropertiesFile(DeploymentCreateResponse response) {
        String esUser = "";
        String esPassword = "";
        String region = "";

        List<DeploymentResource> deploymentResourceList =  response.getResources();
        for (DeploymentResource resource : deploymentResourceList) {
            String kind = resource.getKind();
            if (kind.equals("elasticsearch")) {
                ClusterCredentials clusterCredentials = resource.getCredentials();
                esUser = clusterCredentials.getUsername();
                esPassword = clusterCredentials.getPassword();
                region = resource.getRegion();
                elasticsearchClusterId = resource.getId();
            } else if (kind.equals("kibana")) {
                kibanaClusterId = resource.getId();
            }
        }

        String domain = "foundit.no";
        String port = "9243";
        String provider = "aws.staging";
        if (region.contains("gcp")) {
            provider = "gcp";
            region = region.replace("gcp-","");
        } else if (region.contains("azure")) {
            provider = "staging.azure";
            region = region.replace("azure-","");
        } else if (region.contains("aws-eu-central-1")) {
            provider = "aws";
            region = "eu-central-1";
        }

        String elasticsearch_url = String.format("https://%s.%s.%s.%s:%s", elasticsearchClusterId,
                region, provider, domain, port);
        String kibana_url = String.format("https://%s.%s.%s.%s:%s", kibanaClusterId,
                region, provider, domain, port);

        try {
            Properties properties = new Properties();
            properties.setProperty("deployment_id", deploymentId);
            properties.setProperty("elasticsearch_cluster_id", elasticsearchClusterId);
            properties.setProperty("es_username", esUser);
            properties.setProperty("es_password", esPassword);
            properties.setProperty("kibana_cluster_id", kibanaClusterId);
            properties.setProperty("elasticsearch_url", elasticsearch_url);
            properties.setProperty("kibana_url", kibana_url);
            propertiesFile = DeploymentFile.getFilename(deploymentId);
            File file = new File(propertiesFile);
            FileOutputStream fileOut = new FileOutputStream(file);
            properties.store(fileOut, "Cloud Cluster Info");
            fileOut.close();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private TopologySize getTopologySize() {
        return getTopologySize(1024);
    }

    private TopologySize getTopologySize(int size) {
        return new TopologySize()
                .value(size)
                .resource(TopologySize.ResourceEnum.MEMORY);
    }

    private ElasticsearchPayload getElasticsearchPayload(CloudApi api) {
        final String deploymentTemplate = "aws-io-optimized";

        TopologySize topologySize = getTopologySize();

        ElasticsearchNodeType esNodeType = new ElasticsearchNodeType().data(true).master(true).ingest(false).ml(false);
        ElasticsearchNodeType ingestNodeType = new ElasticsearchNodeType().data(false).master(false).ml(false).ingest(true);
        ElasticsearchNodeType mlNodeType = new ElasticsearchNodeType().data(false).master(false).ingest(false).ml(true);

        ElasticsearchClusterTopologyElement esTopology = new ElasticsearchClusterTopologyElement()
                .instanceConfigurationId(esInstanceCfg)
                .nodeType(esNodeType)
                .zoneCount(1)
                .size(topologySize);

        ElasticsearchClusterTopologyElement ingestTopology = new ElasticsearchClusterTopologyElement()
                .instanceConfigurationId(ingestInstanceCfg)
                .nodeType(ingestNodeType)
                .zoneCount(1)
                .size(topologySize);

        ElasticsearchClusterTopologyElement mlTopology = new ElasticsearchClusterTopologyElement()
                .instanceConfigurationId(mlInstanceCfg)
                .nodeType(mlNodeType)
                .zoneCount(1)
                .size(topologySize);

        ElasticsearchConfiguration esCfg = new ElasticsearchConfiguration()
                .version(stackVersion);

        if (elasticsearchUserSettings != null) {
            esCfg.userSettingsYaml(elasticsearchUserSettings);
        }

        DeploymentTemplateReference templateRef = new DeploymentTemplateReference()
                .id(deploymentTemplate);

        ElasticsearchClusterPlan plan = new ElasticsearchClusterPlan()
                .elasticsearch(esCfg)
                .deploymentTemplate(templateRef);

        if (mlNode && ingestNode) {
            plan.clusterTopology(Arrays.asList(esTopology, mlTopology, ingestTopology));
        } else if (mlNode) {
            plan.clusterTopology(Arrays.asList(esTopology, mlTopology));
        } else if (ingestNode) {
            plan.clusterTopology(Arrays.asList(esTopology, ingestTopology));
        } else {
            plan.clusterTopology(Collections.singletonList(esTopology));
        }

        return new ElasticsearchPayload()
                .plan(plan)
                .region(dataRegion)
                .refId(api.getEsRefId());
    }

    private KibanaPayload getKibanaPayload(CloudApi api) {
        TopologySize topologySize = getTopologySize();

        int kibanaZone;
        try {
            kibanaZone = Integer.parseInt(System.getenv("ESTF_CLOUD_KIBANA_ZONE"));
        } catch (NumberFormatException e) {
            kibanaZone = 1;
        }

        KibanaClusterTopologyElement kbnTopology = new KibanaClusterTopologyElement()
                .instanceConfigurationId(kbnInstanceCfg)
                .zoneCount(kibanaZone)
                .size(topologySize);

        KibanaConfiguration kbnCfg = new KibanaConfiguration()
                .version(stackVersion);

        if (kibanaUserSettings != null) {
            kbnCfg.userSettingsYaml(kibanaUserSettings);
        }

        KibanaClusterPlan kbnPlan = new KibanaClusterPlan()
                .kibana(kbnCfg)
                .clusterTopology(Collections.singletonList(kbnTopology));

        return new KibanaPayload()
                .elasticsearchClusterRefId(api.getEsRefId())
                .refId(api.getKbRefId())
                .plan(kbnPlan)
                .region(dataRegion);
    }

    private ApmPayload getApmPayload(CloudApi api) {
        TopologySize topologySize = getTopologySize(512);

        ApmTopologyElement apmTopology = new ApmTopologyElement()
                .instanceConfigurationId(apmInstanceCfg)
                .zoneCount(1)
                .size(topologySize);

        ApmConfiguration apmCfg = new ApmConfiguration()
                .version(stackVersion);

        ApmPlan apmPlan = new ApmPlan()
                .apm(apmCfg)
                .clusterTopology(Collections.singletonList(apmTopology));

        return new ApmPayload()
                .elasticsearchClusterRefId(api.getEsRefId())
                .refId(api.getApmRefId())
                .plan(apmPlan)
                .region(dataRegion);
    }

    private EnterpriseSearchPayload getEnterpriseSearchPayload(CloudApi api) {
        TopologySize topologySize = getTopologySize(2048);

        EnterpriseSearchNodeTypes enterpriseSearchNodeTypes = new EnterpriseSearchNodeTypes()
                .appserver(true)
                .worker(true)
                .connector(true);

        EnterpriseSearchTopologyElement enterpriseSearchTopologyElementTopology = new EnterpriseSearchTopologyElement()
                .instanceConfigurationId(enterpriseSearchInstanceCfg)
                .nodeType(enterpriseSearchNodeTypes)
                .zoneCount(2)
                .size(topologySize);

        EnterpriseSearchConfiguration ensCfg = new EnterpriseSearchConfiguration()
                .version(stackVersion);

        EnterpriseSearchPlan ensPlan = new EnterpriseSearchPlan()
                .enterpriseSearch(ensCfg)
                .clusterTopology(Collections.singletonList(enterpriseSearchTopologyElementTopology));

        return new EnterpriseSearchPayload()
                .elasticsearchClusterRefId(api.getEsRefId())
                .refId(api.getEnsRefId())
                .plan(ensPlan)
                .region(dataRegion);
    }

    private DeploymentCreateResponse createDeployment(CloudApi cloudApi, DeploymentsApi deploymentsApi) {

        DeploymentCreateResources deploymentCreateResources = new DeploymentCreateResources()
                .addElasticsearchItem(getElasticsearchPayload(cloudApi))
                .addKibanaItem(getKibanaPayload(cloudApi));

        if (apmNode) {
            deploymentCreateResources.addApmItem(getApmPayload(cloudApi));
        }

        if (enterpriseSearchNode) {
            deploymentCreateResources.addEnterpriseSearchItem(getEnterpriseSearchPayload(cloudApi));
        }

        DeploymentCreateResponse response = deploymentsApi.createDeployment(
                new DeploymentCreateRequest()
                        .name("ESTF_Deployment__" + UUID.randomUUID().toString())
                        .resources(deploymentCreateResources),
                "estf_request_id_" + UUID.randomUUID().toString(),
                false);

        deploymentId = response.getId();

        Waiter.setWait(Duration.ofMinutes(20));
        cloudApi.waitForElasticsearch(deploymentsApi, deploymentId);
        cloudApi.waitForKibana(deploymentsApi, deploymentId);

        if (apmNode) {
            cloudApi.waitForApm(deploymentsApi, deploymentId);
        }

        if (enterpriseSearchNode) {
            cloudApi.waitForEnterpriseSearch(deploymentsApi, deploymentId);
        }

        return response;
    }
}
