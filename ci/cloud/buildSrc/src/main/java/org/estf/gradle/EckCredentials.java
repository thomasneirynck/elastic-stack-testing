/*
    Elastic ECK Credentials

    Author: Liza Dayoub

 */

package org.estf.gradle;


import com.bettercloud.vault.Vault;
import com.bettercloud.vault.VaultConfig;
import com.bettercloud.vault.VaultException;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.gradle.api.tasks.Input;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Map;

public class EckCredentials {

    @Input
    String dir;

    private String filename;
    private String username;

    public void vaultAuth() {
        String vaultAddr = System.getenv("VAULT_ADDR");
        String vaultToken = System.getenv("VAULT_TOKEN");
        String vaultPath = System.getenv("VAULT_PATH");

        if (vaultPath == null) {
            vaultPath = "secret/stack-testing/eck";
        }

        if (vaultAddr == null || vaultToken == null) {
            throw new Error("Environment variables: VAULT_ADDR and VAULT_TOKEN are required");
        }

        try {
            final VaultConfig config = new VaultConfig()
                                            .address(vaultAddr)
                                            .token(vaultToken)
                                            .build();

            final Vault vault = new Vault(config);
            final Map map = vault.logical()
                                    .read(vaultPath)
                                    .getData();

            String policy = map.get("policy").toString();

            JsonElement jsonElement = new JsonParser().parse(policy);
            JsonObject jsonObject = jsonElement.getAsJsonObject();
            this.username = jsonObject.get("client_email").getAsString();
            this.filename = dir + "/eck_key.json";

            try {
                Files.write(Paths.get(filename), policy.getBytes());
            } catch(IOException e) {
                throw new Error("Caught File Exception: " + e.getMessage());
            }

        } catch(VaultException e) {
            throw new Error("Caught Vault Exception: " + e.getMessage());
        }
    }

    public String getFileName() {
        return this.filename;
    }
    public String getUserName() {
        return this.username;
    }
}

