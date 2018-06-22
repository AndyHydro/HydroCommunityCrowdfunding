pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./ownership/Ownable.sol";
import "./ERC20/ERC20.sol";
import "./math/SafeMath.sol";
import "./libraries/addressSet.sol";

contract HydroCrowdFunding is Ownable {
    using SafeMath for uint;
    using addressSet for addressSet._addressSet;

    uint balance;
    bool donationsAllowed;
    addressSet._addressSet internal admins;
    address hydroTokenAddress;

    struct Distribution {
        address to;
        uint amount;
        addressSet._addressSet vetos;
        bool open;
        uint startingTime;
    }

    Distribution[] distributions;

    modifier onlyAdmin() {
        require(admins.contains(msg.sender));
        _;
    }

    modifier onlyDonationsAllowed() {
        require(donationsAllowed);
        _;
    }

    function setHydroTokenAddress(address _address) public onlyOwner {
        hydroTokenAddress = _address;
    }

    function addAdmin(address _admin) public onlyOwner {
        admins.insert(_admin);
    }

    function allowDonations(bool _allow) public onlyAdmin {
        donationsAllowed = _allow;
    }

    function receiveApproval(address _sender, uint _amount, address _tokenAddress, bytes) public onlyDonationsAllowed {
        require(msg.sender == _tokenAddress);
        require(_tokenAddress == hydroTokenAddress);
        deposits[_sender] = deposits[_sender].add(_amount);
        balance = balance.add(_amount);
        ERC20 hydro = ERC20(_tokenAddress);
        require(hydro.transferFrom(_sender, address(this), _amount));

        emit CrowdfundDeposit(_sender, _amount);
    }

    function initiateFundDistribution(uint _amount, address _to) public onlyAdmin {
        require(balance >= _amount);
        require(!distributions[distributions.length - 1].open);

        Distribution memory dist;
        dist.amount = _amount;
        dist.to = _to;
        dist.open = true;
        dist.startingTime = block.timestamp;

        distributions.push(dist);

        FundDistributionInitiated(
          distributions[distributions.length - 1].to,
          distributions[distributions.length - 1].amount,
          distributions[distributions.length - 1].startingTime
        );
    }

    function distributeFunds() public {
        require(distributions[distributions.length - 1].startingTime + 3 days < block.timestamp);
        require(distributions[distributions.length - 1].vetos.members.length < 2);
        require(distributions[distributions.length - 1].amount <= balance);

        distributions[distributions.length - 1].open = false;
        ERC20 hydro = ERC20(_tokenAddress);
        require(hydro.transfer(distributions[distributions.length - 1].to, distributions[distributions.length - 1].amount));

        FundsDistributed(
          distributions[distributions.length - 1].to,
          distributions[distributions.length - 1].amount,
          distributions[distributions.length - 1].startingTime
        );
    }

    function vetoDistribution() {
        require(distributions[distributions.length - 1].open);
        require(!distributions[distributions.length - 1].vetos.contains(msg.sender));

        distributions[distributions.length - 1].vetos.insert(msg.sender);

        DistributionVetoed(
          msg.sender,
          distributions[distributions.length - 1].vetos.members.length,
          distributions[distributions.length - 1].to,
          distributions[distributions.length - 1].amount
        );
    }

    function closeDistribution() {
        if (distributions[distributions.length - 1].vetos >= 2) {
            distributions[distributions.length - 1].open = false;
            DistributionClosed(
              distributions[distributions.length - 1].to,
              distributions[distributions.length - 1].amount,
              distributions[distributions.length - 1].startingTime
            );
        }
        if (distributions[distributions.length - 1].amount > balance) {
            distributions[distributions.length - 1].open = false;
            DistributionClosed(
              distributions[distributions.length - 1].to,
              distributions[distributions.length - 1].amount,
              distributions[distributions.length - 1].startingTime
            );
        }
    }

    event CrowdfundDeposit(address _sender, uint _amount);
    event FundDistributionInitiated(address _to, uint _amount, uint _startTime);
    event FundsDistributed(address _to, uint _amount, uint _startTime);
    event DistributionClosed(address _to, uint _amount, uint _startTime);
    event DistributionVetoed(address _veto, uint _vetoCount, address _to, uint _amount);

}
