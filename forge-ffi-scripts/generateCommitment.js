const ethers = require("ethers");
const { pedersenHash } = require("./utils/pedersen.js");
const { rbigint, bigintToHex, leBigintToBuffer } = require("./utils/bigint.js");
// Intended output: (bytes32 commitment, bytes32 nullifier, bytes32 secret)
////////////////////////////// MAIN ///////////////////////////////////////////
async function main() {
  // 1. Generate random nullifier and secret
  const amountHex = process.argv[2];
  const nullifier = rbigint(31);
  const secret = rbigint(31);
  const amount = BigInt(amountHex);

  // 2. Get commitment
  const commitment = await pedersenHash(
    Buffer.concat([
      leBigintToBuffer(nullifier, 31),
      leBigintToBuffer(secret, 31),
      leBigintToBuffer(amount, 8),
    ])
  );

  // 3. Return abi encoded nullifier, secret, commitment
  const res = ethers.utils.defaultAbiCoder.encode(
    ["bytes32", "bytes32", "bytes32", "bytes32"],
    [
      bigintToHex(commitment),
      bigintToHex(nullifier),
      bigintToHex(amount),
      bigintToHex(secret),
    ]
  );

  return res;
}

main()
  .then((res) => {
    process.stdout.write(res);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
