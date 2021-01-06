package org.estf.gradle;

import java.io.File;

/**
 * DeploymentFile
 *
 * @author  Liza Dayoub
 *
 */
public class DeploymentFile {
    public static String getFilename(String clusterId) {
        String workspaceDir = System.getenv("WORKSPACE");
        if (workspaceDir == null || workspaceDir.trim().isEmpty()) {
            workspaceDir = new File("").getAbsoluteFile().toString();
        }
        File dir = new File(workspaceDir);
        boolean isDirectory = dir.isDirectory();
        if (! isDirectory) {
            throw new Error("Environment WORKSPACE is required, not a dir: " + workspaceDir);
        }
        return workspaceDir + '/' + clusterId + ".properties";
    }
}