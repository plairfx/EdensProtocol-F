// SPDX-LICENSE-IDENTIFIER: MIT
import {CCIPReceiver} from "lib/chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "lib/chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "lib/chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

pragma solidity ^0.8.23;

contract FakeCCIP {
    address router = 0x4B2AEa91Ed33FFb3783e545cc5F975174dC53EF0;
    uint64 destChain = 16015286601757825753;

    function send(uint64 destinationChainSelector, address receiver, bytes memory _data)
        public
        returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 1_000_000, allowOutOfOrderExecution: true})),
            feeToken: address(0)
        });

        uint256 fee = IRouterClient(router).getFee(destChain, message);

        messageId = IRouterClient(router).ccipSend{value: fee}(destChain, message);

        // emit MessageSent(messageId);
    }
}
