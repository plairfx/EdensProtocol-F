interface IEdenPL {
    function depositFees() external returns (uint256);

    function getFeesAccumulated() external view returns (uint256);
}
