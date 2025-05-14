import { PolynanceSDK } from "polynance_sdk";
import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import dotenv from "dotenv";
dotenv.config();

async function main() {
  try {
    const forkPolygonRpc = process.env.POLYGON_RPC_URL;
    const testPrivateKey = process.env.PRIVATE_KEY;

    if(!forkPolygonRpc || !testPrivateKey) {
        throw new Error("POLYGON_RPC_URL or PRIVATE_KEY is not set");
    }
    const wallet = new Wallet(testPrivateKey, new JsonRpcProvider(forkPolygonRpc));

    //⚡️ Polynance SDK
    const sdk = new PolynanceSDK({wallet});

    const provider = "polymarket";
    const slug = "will-google-have-the-top-ai-model-on-may-31";
    const binary = "YES";
    const buyOrSell = "BUY";
    const fundingUsdc = 10;

    const signedOrder = await sdk.buildOrder({
        provider,
        marketIdOrSlug: slug,
        positionIdOrName: binary,
        buyOrSell,
        usdcFlowAbs: fundingUsdc,
    });
    console.log("Executing order...", signedOrder);
    //Execute Order
    const result = await sdk.executeOrder(signedOrder); //propose price is in here
    console.log("open order: ", sdk.asContext(result));

    //position
    console.log("Getting positions...");
    const currentPosition = await sdk.traderPositions("polymarket", wallet.address);
    console.log("user polymarket positions", currentPosition);

    //verify price
    console.log("Starting verification interval...");
    setInterval(async () => {
      try {
        const verifyAble = await sdk.scanPendingPriceData();
        const orderIds = sdk.getPendingOrdersIds();
        console.log("scanPendingPriceData", verifyAble);
        console.log("pendingPriceData", orderIds);
        if(verifyAble) {
            await sdk.verifyPrice(); //send oracle tx bia server
        } else {
            console.log("no pending price data");
        }
      } catch (error) {
        console.error("Error in verification interval:", error);
      }
    }, 2000);
  } catch (error) {
    console.error("Error in main function:", error);
  }
}

// Run the main function
main().catch(error => {
  console.error("Unhandled error:", error);
});