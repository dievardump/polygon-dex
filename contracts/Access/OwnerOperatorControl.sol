// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract OwnerOperatorControl is AccessControlUpgradeable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    function __OwnerOperatorControl_init() internal {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Role: not Admin");
        _;
    }

    modifier onlyOperator() {
        require(isOperator(_msgSender()), "Role: not Operator");
        _;
    }

    function isOperator(address _address) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, _address);
    }

    function addOperators(address[] calldata operators) external onlyOwner {
        for (uint256 i; i < operators.length; i++) {
            require(
                operators[i] != address(0),
                "Can't grant Role to null address"
            );
            grantRole(OPERATOR_ROLE, operators[i]);
        }
    }

    function removeOperators(address[] calldata operators) external onlyOwner {
        for (uint256 i; i < operators.length; i++) {
            revokeRole(OPERATOR_ROLE, operators[i]);
        }
    }
}
