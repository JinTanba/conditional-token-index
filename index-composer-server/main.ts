import { ExecuteOrderParams, PolynanceSDK } from "polynance_sdk";
import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import dotenv from "dotenv";
dotenv.config();

async function main() {
  try {
    const forkPolygonRpc = process.env.POLYGON_RPC;
    const testPrivateKey = process.env.PRIVATE_KEY;

    if(!forkPolygonRpc || !testPrivateKey) {
        throw new Error("POLYGON_RPC_URL or PRIVATE_KEY is not set");
    }
    const wallet = new Wallet(testPrivateKey, new JsonRpcProvider(forkPolygonRpc));

    //⚡️ Polynance SDK
    const sdk = new PolynanceSDK({wallet,apiBaseUrl:"http://localhost:9000"});

    const orders : ExecuteOrderParams[] = [
      {
        provider: "polymarket",
        marketIdOrSlug: "519068",
        positionIdOrName: "YES",
        buyOrSell: "SELL",
        usdcFlowAbs: 6,
      },
      {
        provider: "polymarket",
        marketIdOrSlug: "519066",
        positionIdOrName: "NO",
        buyOrSell: "SELL",
        usdcFlowAbs: 6,
      },
      {
        provider: "polymarket",
        marketIdOrSlug: "535793",
        positionIdOrName: "YES",
        buyOrSell: "SELL",
        usdcFlowAbs: 6,
      },
      {
        provider: "polymarket",
        marketIdOrSlug: "will-the-indiana-pacers-win-the-2025-nba-finals",
        positionIdOrName: "YES",
        buyOrSell: "SELL",
        usdcFlowAbs: 6,
      },
      {
        provider: "polymarket",
        marketIdOrSlug: "will-xai-have-the-top-ai-model-on-december-31",
        positionIdOrName: "NO",
        buyOrSell: "SELL",
        usdcFlowAbs: 6,
      }
    ];

    //Execute Order
    for(const order of orders) {
      const signedOrder = await sdk.buildOrder(order);
      console.log("Executing order...", signedOrder);
      //Execute Order
      const result = await sdk.executeOrder(signedOrder); //propose price is in here
      console.log("open order: ", sdk.asContext(result));
    }

    setInterval(async () => {
      try {
        const verifyAble = await sdk.scanPendingPriceData();
        const orderIds = sdk.getPendingOrdersIds();
        console.log("scanPendingPriceData", verifyAble);
        console.log("pendingPriceData", orderIds);
        if(verifyAble) {
            //execute indexfactory and check
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