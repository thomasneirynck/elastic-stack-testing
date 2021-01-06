package org.estf.gradle;

import co.elastic.cloud.api.client.generated.DeploymentsApi;
import co.elastic.cloud.api.model.generated.*;
import co.elastic.cloud.api.util.Waiter;
import com.bettercloud.vault.VaultException;
import io.swagger.client.ApiClient;

import java.io.IOException;
import java.time.Duration;

import org.gradle.api.DefaultTask;
import org.gradle.api.tasks.TaskAction;
import org.gradle.api.tasks.Input;

/**
 * UpgradeEssDeployment
 *
 * @author  Liza Dayoub
 *
 */
public class UpgradeEssDeployment extends DefaultTask {

    @Input
    public  String deploymentId = null;

    @Input
    public String upgradeStackVersion = null;

    @TaskAction
    public void run() throws IOException, VaultException {
        if (deploymentId == null || deploymentId.trim().isEmpty()) {
            throw new Error(this.getClass().getSimpleName() + ": deploymentId is required input");
        }

        if (upgradeStackVersion == null || upgradeStackVersion.trim().isEmpty()) {
            throw new Error(this.getClass().getSimpleName() + ": upgradeStackVersion is required input");
        }

        CloudApi cloudApi = new CloudApi();
        ApiClient apiClient = cloudApi.getApiClient();
        DeploymentsApi deploymentsApi = new DeploymentsApi(apiClient);
        updateDeployment(cloudApi, deploymentsApi);
    }

    private void updateDeployment(CloudApi cloudApi, DeploymentsApi deploymentsApi) {

        DeploymentGetResponse deploymentGetResponse = deploymentsApi.getDeployment(deploymentId,
                false,
                true,
                true,
                false,
                false,
                false,
                false,
                0,
                true,
                false);

        ElasticsearchResourceInfo esResourceInfo = deploymentsApi.getDeploymentEsResourceInfo(deploymentId,
                cloudApi.getEsRefId(),
                false,
                true,
                true,
                false,
                false,
                true,
                false,
                0,
                true,
                false);

        ElasticsearchClusterPlan esPlan =  esResourceInfo
                .getInfo()
                .getPlanInfo()
                .getCurrent()
                .getPlan();

        for (int i=0; i < esPlan.getClusterTopology().size(); i++) {

            ElasticsearchSystemSettings elasticsearchSystemSettings = esPlan
                    .getClusterTopology()
                    .get(i)
                    .getElasticsearch()
                    .getSystemSettings();

            ElasticsearchScriptTypeSettings typeSetting = new ElasticsearchScriptTypeSettings()
                    .enabled(true)
                    .sandboxMode(null);

            ElasticsearchScriptingUserSettings elasticsearchScriptingSettings = new ElasticsearchScriptingUserSettings()
                    .expressionsEnabled(null)
                    .file(null)
                    .inline(typeSetting)
                    .stored(typeSetting)
                    .mustacheEnabled(null)
                    .painlessEnabled(null);

            ElasticsearchConfiguration esCfg = esPlan.getElasticsearch()
                    .version(upgradeStackVersion)
                    .systemSettings(elasticsearchSystemSettings
                                        .scripting(elasticsearchScriptingSettings)
                                        .watcherTriggerEngine(null));

            esPlan.getClusterTopology().get(i).setElasticsearch(esCfg);
            esPlan.getClusterTopology().get(i).setSize(new TopologySize()
                                                        .value(1024)
                                                        .resource(TopologySize.ResourceEnum.MEMORY));
        }

        KibanaResourceInfo kbnResourceInfo = deploymentsApi.getDeploymentKibResourceInfo(deploymentId,
                cloudApi.getKbRefId(),
                false,
                true,
                true,
                false,
                false,
                false,
                false);

        KibanaClusterPlan kbnPlan =  kbnResourceInfo.getInfo()
                .getPlanInfo()
                .getCurrent()
                .getPlan();

        ApmResourceInfo apmResourceInfo = null;
        ApmPlan apmPlan = null;
        try {
            apmResourceInfo = deploymentsApi.getDeploymentApmResourceInfo(deploymentId,
                    cloudApi.getApmRefId(),
                    false,
                    true,
                    true,
                    false,
                    false,
                    false);

            apmPlan = apmResourceInfo.getInfo()
                    .getPlanInfo()
                    .getCurrent()
                    .getPlan();
        } catch (Exception ignored) {}

        EnterpriseSearchResourceInfo ensResourceInfo = null;
        EnterpriseSearchPlan ensPlan = null;
        try {
            ensResourceInfo = deploymentsApi.getDeploymentEnterpriseSearchResourceInfo(deploymentId,
                    cloudApi.getEnsRefId(),
                    false,
                    true,
                    true,
                    false,
                    false,
                    false);

            ensPlan = ensResourceInfo.getInfo()
                    .getPlanInfo()
                    .getCurrent()
                    .getPlan();
        } catch(Exception ignored) {}

        DeploymentUpdateResources deploymentUpdateResources = new DeploymentUpdateResources()
                .addElasticsearchItem(new ElasticsearchPayload()
                        .region(esResourceInfo.getRegion())
                        .refId(esResourceInfo.getRefId())
                        .plan(esPlan))
                .addKibanaItem(new KibanaPayload()
                        .elasticsearchClusterRefId(kbnResourceInfo.getElasticsearchClusterRefId())
                        .region(kbnResourceInfo.getRegion())
                        .refId(kbnResourceInfo.getRefId())
                        .plan(kbnPlan));

        if (apmPlan != null) {
            deploymentUpdateResources.addApmItem(new ApmPayload()
                    .elasticsearchClusterRefId(apmResourceInfo.getElasticsearchClusterRefId())
                    .region(apmResourceInfo.getRegion())
                    .refId(apmResourceInfo.getRefId())
                    .plan(apmPlan));
        }

        if (ensPlan != null) {
            deploymentUpdateResources.addEnterpriseSearchItem(new EnterpriseSearchPayload()
                    .elasticsearchClusterRefId(ensResourceInfo.getElasticsearchClusterRefId())
                    .region(ensResourceInfo.getRegion())
                    .refId(ensResourceInfo.getRefId())
                    .plan(ensPlan));
        }

        DeploymentUpdateRequest deploymentUpdateRequest = new DeploymentUpdateRequest()
                .name(deploymentGetResponse.getName())
                .pruneOrphans(true)
                .resources(deploymentUpdateResources);

        DeploymentUpdateResponse response = deploymentsApi.updateDeployment(deploymentId,
                deploymentUpdateRequest,
                false,
                false,
                false,
                null);

        Waiter.setWait(Duration.ofMinutes(20));

        cloudApi.waitForElasticsearch(deploymentsApi, deploymentId);
        cloudApi.waitForKibana(deploymentsApi, deploymentId);

        deploymentsApi.upgradeDeploymentStatelessResource(deploymentId,
                "kibana",
                cloudApi.getKbRefId(),
                false);
        cloudApi.waitForKibana(deploymentsApi, deploymentId);

        if (apmPlan != null) {
            deploymentsApi.upgradeDeploymentStatelessResource(deploymentId,
                    "apm",
                    cloudApi.getApmRefId(),
                    false);
            cloudApi.waitForApm(deploymentsApi, deploymentId);
        }

        if (ensPlan != null) {
            deploymentsApi.upgradeDeploymentStatelessResource(deploymentId,
                    "enterprise_search",
                    cloudApi.getEnsRefId(),
                    false);
            cloudApi.waitForEnterpriseSearch(deploymentsApi, deploymentId);
        }

    }
}