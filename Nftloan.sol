//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NftLoan {
    struct Loan {
        //Amount in wei
        uint256 amount;
        uint256 nftId;
        uint256 loaningTimeEndTimestamp;
        uint256 loanDuration;
        uint256 loanDurationEndTimestamp;
        address nftAddress;
        address payable borrower;
        address payable lender;
        Status status;
    }

    enum Status {
        Open,
        Loaned,
        Closed
    }

    mapping(uint256 => Loan) loanList;
    // keeps track of loans that exist
    mapping(uint256 => bool) private exist;

    // keeps track of Nfts that are on loan
    // key address is address of The NFT smart contract
    mapping(address => mapping(uint256 => bool)) public onLoan;

    using Counters for Counters.Counter;

    Counters.Counter private _loanIdCounter;

    //Modifiers

    modifier correctAmount(uint256 _loanId) {
        require(
            msg.value == loanList[_loanId].amount,
            "Send the correct amount"
        );
        _;
    }

    modifier onlyBorrower(uint256 _loanId) {
        require(
            msg.sender == loanList[_loanId].borrower,
            "Only the borrower can access this function"
        );
        _;
    }

    modifier isOpen(uint256 _loanId) {
        require(loanList[_loanId].status == Status.Open, "Loan is not open");
        _;
    }

    modifier isLoaned(uint256 _loanId) {
        require(
            loanList[_loanId].status == Status.Loaned,
            "The loan is not in loaned state"
        );
        _;
    }

    modifier exists(uint256 _loanId) {
        require(exist[_loanId], "Query of non existent loan");
        _;
    }

    //Events
    event newLoan(address borrower, uint256 indexed loanId);

    event loaned(
        address borrower,
        address lender,
        uint256 indexed loanId,
        uint256 amount
    );

    event requestClosed(address borrower, uint256 indexed loanId);

    event loanRepayed(
        address borrower,
        address lender,
        uint256 indexed loanId,
        uint256 amount
    );

    event nftCeased(address borrower, address lender, uint256 indexed loanId);

    //----------------------------------------------------------------------------------------------------------------------

    //Function using which the users can make a loan request
    function askForLoan(
        uint256 _nftId,
        address _nft,
        uint256 _amount,
        uint256 _loanClosingDuration,
        uint256 _loanDuration
    ) public {
        require(!onLoan[_nft][_nftId], "Nft is currently in a loan");
        require(_amount > 0, "Amount can't be zero");
        require(_nft != address(0), "Non existent nft contract");
        require(
            _loanDuration > 0 && _loanClosingDuration > 0,
            "Invalid duration values"
        );
        require(
            IERC721(_nft).ownerOf(_nftId) == msg.sender &&
                IERC721(_nft).getApproved(_nftId) == address(this),
            "Invalid caller or contract hasn't been approved"
        );
        IERC721(_nft).transferFrom(msg.sender, address(this), _nftId);
        //Duration is in minutes for testing purpose
        uint256 loanClosingTimeStamp = block.timestamp +
            _loanClosingDuration *
            1 minutes;
        uint256 id = _loanIdCounter.current();
        loanList[id] = Loan(
            _amount,
            _nftId,
            loanClosingTimeStamp,
            _loanDuration,
            0,
            _nft,
            payable(msg.sender),
            payable(address(0)),
            Status.Open
        );
        exist[id] = true;
        onLoan[_nft][_nftId] = true;
        emit newLoan(msg.sender, id);
        _loanIdCounter.increment();
    }

    //Other users can use this function to lend money to the loan
    function lendMoney(uint256 _loanId)
        public
        payable
        exists(_loanId)
        correctAmount(_loanId)
        isOpen(_loanId)
    {
        Loan storage loan = loanList[_loanId];
        require(msg.sender != loan.borrower, "You cannot loan yourself");
        require(
            block.timestamp < loan.loaningTimeEndTimestamp,
            "Loan open time ended"
        );
        (bool success, ) = loan.borrower.call{value: loan.amount}("");
        require(success, "Failed to loan to borrower");
        //Duration is in minutes for testing purpose
        loan.loanDurationEndTimestamp =
            block.timestamp +
            loan.loanDuration *
            1 minutes;
        loan.lender = payable(msg.sender);
        loan.status = Status.Loaned;
        emit loaned(loan.borrower, loan.lender, _loanId, loan.amount);
    }

    //If no one lends money in the particular window, users can close the request and get their NFT back
    function closeBorrowRequest(uint256 _loanId)
        public
        exists(_loanId)
        onlyBorrower(_loanId)
        isOpen(_loanId)
    {
        Loan storage loan = loanList[_loanId];
        require(
            block.timestamp > loan.loaningTimeEndTimestamp,
            "The loan is still open"
        );
        IERC721(loan.nftAddress).transferFrom(
            address(this),
            msg.sender,
            loan.nftId
        );
        loan.status = Status.Closed;
        onLoan[loan.nftAddress][loan.nftId] = false;
        emit requestClosed(msg.sender, _loanId);
    }

    //Function using which the borrower can return the money and get his NFT back
    function repayLoan(uint256 _loanId)
        public
        payable
        exists(_loanId)
        correctAmount(_loanId)
        onlyBorrower(_loanId)
        isLoaned(_loanId)
    {
        Loan storage loan = loanList[_loanId];
        require(
            loan.loanDurationEndTimestamp > block.timestamp,
            "Loan duration Ended"
        );
        (bool success, ) = loan.lender.call{value: loan.amount}("");
        require(success, "Failed to pay back lender");
        IERC721(loan.nftAddress).transferFrom(
            address(this),
            msg.sender,
            loan.nftId
        );
        onLoan[loan.nftAddress][loan.nftId] = false;
        loan.status = Status.Closed;
        emit loanRepayed(msg.sender, loan.lender, _loanId, loan.amount);
    }

    //If the borrower fails to pay back the money, after the loan duration ends, the nft is transfered to the lender
    function ceaseNft(uint256 _loanId)
        public
        exists(_loanId)
        isLoaned(_loanId)
    {
        Loan storage loan = loanList[_loanId];
        require(msg.sender == loan.lender, "Only the lender can cease the NFT");
        require(
            loan.loanDurationEndTimestamp < block.timestamp,
            "Loan duration not over"
        );
        IERC721(loan.nftAddress).transferFrom(
            address(this),
            msg.sender,
            loan.nftId
        );
        loan.status = Status.Closed;
        onLoan[loan.nftAddress][loan.nftId] = false;
        emit nftCeased(loan.borrower, loan.lender, _loanId);
    }

    //View funciton that returns the required details of the loan
    function getDetails(uint256 _loanId)
        public
        view
        exists(_loanId)
        returns (
            uint256 amount,
            uint256 nftId,
            uint256 loaningTimeEndTimestamp,
            uint256 loanDuration,
            uint256 loanDurationEndTimestamp,
            address nftAddress,
            address payable borrowerAddress,
            address payable lenderAddress,
            Status status
        )
    {
        Loan storage loan = loanList[_loanId];
        return (
            loan.amount,
            loan.nftId,
            loan.loaningTimeEndTimestamp,
            loan.loanDuration,
            loan.loanDurationEndTimestamp,
            loan.nftAddress,
            loan.borrower,
            loan.lender,
            loan.status
        );
    }
}
