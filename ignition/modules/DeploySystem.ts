import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SystemModule = buildModule("SystemModule", (m) => {
  // 1. Deploy Token $HASH dulu
  const hashToken = m.contract("HashToken");

  // 2. Deploy Game Contract, masukkan address Token sebagai argumen constructor
  const game = m.contract("CyberArtifacts", [hashToken]);

  // 3. PENTING: Transfer kepemilikan Token ke Game Contract
  // Agar Game Contract bisa memanggil fungsi 'mint' di Token Contract.
  m.call(hashToken, "transferOwnership", [game]);

  return { hashToken, game };
});

export default SystemModule;