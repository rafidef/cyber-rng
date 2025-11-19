import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const CyberArtifactsModule = buildModule("CyberArtifactsModule", (m) => {
  const cyberArtifacts = m.contract("CyberArtifacts");
  return { cyberArtifacts };
});

export default CyberArtifactsModule;