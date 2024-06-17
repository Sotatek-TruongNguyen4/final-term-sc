import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  console.log(`Deploying marketplace contract with the account: ${deployer}`);
  const market = await deploy("NFTMarketplace", {
    from: deployer,
    log: true,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [process.env.TREASURY_ADDRESS],
        },
      },
    },
  });

  console.log(`Marketplace contract: `, market.address);
};
export default func;

func.id = "nftmarketplace_deployment"; // id required to prevent reexecution
func.tags = ["NFTMarketplace"];
