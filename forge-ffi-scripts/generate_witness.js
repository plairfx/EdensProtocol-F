const path = require("path");
const snarkjs = require("snarkjs");
const ethers = require("ethers");
const {
  hexToBigint,
  bigintToHex,
  leBigintToBuffer,
} = require("./utils/bigint.js");
const { pedersenHash } = require("./utils/pedersen.js");
const { mimicMerkleTree } = require("./utils/mimcMerkleTree.js");
// Intended output: (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, bytes32 root, bytes32 nullifierHash)
////////////////////////////// MAIN ///////////////////////////////////////////
async function main() {
  const inputs = process.argv.slice(2, process.argv.length);

  // 1. Get nullifier and secret
  const nullifier = hexToBigint(inputs[0]);
  const secret = hexToBigint(inputs[1]);
  const amount = hexToBigint(inputs[2]);
  
  // 2. Get nullifier hash
  const nullifierHash = await pedersenHash(leBigintToBuffer(nullifier, 31));
  
  // 3. Create merkle tree, insert leaves and get merkle proof for commitment

  // Get leaves from inputs (starting from the 7th argument)


  const commitment = await pedersenHash(
    Buffer.concat([
      leBigintToBuffer(nullifier, 31),
      leBigintToBuffer(secret, 31),
      leBigintToBuffer(amount, 8),
    ])
  );
  
  const leaves = inputs.slice(7 , inputs.length).map((l) => hexToBigint(l));

  const tree = await mimicMerkleTree(leaves);

  
  const merkleProof = tree.proof(commitment);
  
  // 4. Format witness input to exactly match circuit expectations
  const input = {
    // Public inputs  // check
    root: merkleProof.pathRoot, 
    nullifierHash: nullifierHash,
    amount: amount,
    recipient: hexToBigint(inputs[3]),
    relayer: hexToBigint(inputs[4]),
 
    fee: BigInt(inputs[5]),
    refund: BigInt(inputs[6]),


    // Private inputs // check
    nullifier: nullifier,
    secret: secret,
    pathElements: merkleProof.pathElements.map((x) => x.toString()),
    pathIndices: merkleProof.pathIndices,
  };
  
  // 5. Create groth16 proof for witness
  const { proof } = await snarkjs.groth16.fullProve(
    input,
    path.join(__dirname, "../outputs/withdraw_js/withdraw.wasm"),
    path.join(__dirname, "../outputs/withdraw.zkey")
  );
  
  const pA = proof.pi_a.slice(0, 2);
  const pB = proof.pi_b.slice(0, 2);
  const pC = proof.pi_c.slice(0, 2);
  
  // 6. Return abi encoded witness
  const witness = ethers.utils.defaultAbiCoder.encode(
    ["uint256[2]", "uint256[2][2]", "uint256[2]",  "bytes32", "bytes32", "bytes32"],
    [
      pA,
      // Swap x coordinates: this is for proof verification with the Solidity precompile for EC Pairings, and not required
      // for verification with e.g. snarkJS.
      [
        [pB[0][1], pB[0][0]],
        [pB[1][1], pB[1][0]],
      ],
      pC,
      bigintToHex(merkleProof.pathRoot),
      bigintToHex(nullifierHash),
      bigintToHex(amount),
    ]
  );
  
  return witness;
}

main()
  .then((wtns) => {
    process.stdout.write(wtns);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });