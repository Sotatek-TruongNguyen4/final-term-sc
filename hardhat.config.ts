import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig, NetworkUserConfig } from "hardhat/config";

// Load environment variables
dotEnvConfig();

// Chain IDs
const chainIds = {
  hardhat: 31337,
  bsc: 97,
};

// Function to get network configuration
function getChainConfig(chain: keyof typeof chainIds): NetworkUserConfig {
  const jsonRpcUrl = process.env.BSC_RPC_URL as string;

  if (chain === "hardhat") {
    return {
      chainId: chainIds.hardhat,
      accounts: {
        count: 10,
      },
    };
  }

  return {
    accounts: [process.env.PRIVATE_KEY as string],
    chainId: chainIds[chain],
    url: jsonRpcUrl,
  };
}

// Hardhat configuration
const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: 0,
  },
  networks: {
    bsc: getChainConfig("bsc"),
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    version: "0.8.20",
    settings: {
      metadata: {
        bytecodeHash: "none",
      },
      optimizer: {
        enabled: true,
        runs: 800,
        details: {
          yulDetails: {
            optimizerSteps: "u",
          },
        },
      },
      viaIR: true,
    },
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
};

export default config;
