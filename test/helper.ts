import {
  createWalletClient,
  http,
  keccak256,
  encodePacked,
  WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bscTestnet } from "viem/chains";

export async function getOffchainXAUPrice() {
  const data = await fetch(
    "https://price_future_gold.algofeed.com/api/price?symbol=XAUUSD&api_key=sk-902798m9u80c2mx0-xrfu3h9entvg0nh48"
  );
  return (await data.json()) as {
    symbol: string;
    bid: number;
    ask: number;
    timestamp: number;
  };
  // {
  //   symbol: 'XAUUSD',
  //   bid: 4210.835978742819,
  //   ask: 4212.608861052538,
  //   timestamp: 1765336624150
  // }
}

export async function sign(
  walletClient: WalletClient,
  offchainPrice: bigint,
  deadline: bigint,
  userWallet: `0x${string}`
) {
  const messageHash = keccak256(
    encodePacked(
      ["uint256", "uint256", "address"],
      [offchainPrice, deadline, userWallet]
    )
  );

  //@ts-ignore
  const signature = await walletClient.signMessage({
    message: {
      raw: messageHash,
    },
  });
  return signature;
}

export async function sign_with_privateKey(
  offchainPrice: bigint,
  deadline: bigint,
  userWallet: `0x${string}`
) {
  const account = privateKeyToAccount(
    "0xdf57089febbacf7ba0bc227dafbffa9fc08a93fdc68e1e42411a14efcf23656e"
  );

  const walletClient = createWalletClient({
    account,
    chain: bscTestnet,
    transport: http(),
  });

  return sign(walletClient, offchainPrice, deadline, userWallet);
}
