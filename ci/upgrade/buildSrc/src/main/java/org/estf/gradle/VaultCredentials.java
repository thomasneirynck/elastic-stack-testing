package org.estf.gradle;

import com.bettercloud.vault.Vault;
import com.bettercloud.vault.VaultConfig;
import com.bettercloud.vault.VaultException;

import java.io.IOException;

/**
 * CloudCredentials
 *
 * @author  Liza Dayoub
 *
 */
public class VaultCredentials {

    private String apiKey;
    private String vaultPath;
    private final String vaultAddress;
    private final String vaultToken;

    public VaultCredentials() throws IOException, VaultException {
        vaultAddress = System.getenv("VAULT_ADDR");
        vaultToken = System.getenv("VAULT_TOKEN");
        vaultPath = System.getenv("VAULT_PATH");

        if (vaultAddress == null || vaultAddress.trim().isEmpty()) {
            throw new IOException(this.getClass().getSimpleName() + ": vaultAddress is required");
        }
        if (vaultToken == null || vaultToken.trim().isEmpty()){
            throw new IOException(this.getClass().getSimpleName() + ": vaultToken is required");
        }
        if (vaultPath == null || vaultPath.trim().isEmpty()) {
            vaultPath = "secret/stack-testing/estf-cloud-staging";
        }
        setApiKey();
    }

    private void setApiKey() throws VaultException {
        final VaultConfig config = new VaultConfig()
                .engineVersion(1)
                .address(vaultAddress)
                .token(vaultToken)
                .build();
        final Vault vault = new Vault(config);
        apiKey = vault.withRetries(10, 1000)
                .logical()
                .read(vaultPath)
                .getData()
                .get("apiKey");
    }

    public String getApiKey() {
        return apiKey;
    }

} 
