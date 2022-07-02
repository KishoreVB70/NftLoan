//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NftLoan {
    using Counters for Counters.Counter;

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

    Counters.Counter public loanId;

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
        require(loanList[_loanId].status == Status.Open, "Loan is not Open");
        _;
    }

    modifier isLoaned(uint256 _loanId) {
        require(
            loanList[_loanId].status == Status.Loaned,
            "The loan is not in loaned state"
        );
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
        uint256 _loanId = loanId.current();
        loanId.increment();
        IERC721(_nft).transferFrom(msg.sender, address(this), _nftId);
        //Duration is in minutes for testing purpose
        uint256 loanClosingTimeStamp = block.timestamp +
            (_loanClosingDuration * 1 minutes);
        loanList[_loanId] = Loan(
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
        emit newLoan(msg.sender, _loanId);
    }

    //Other users can use this function to lend money to the loan
    function lendMoney(uint256 _loanId)
        public
        payable
        correctAmount(_loanId)
        isOpen(_loanId)
    {
        Loan storage loan = loanList[_loanId];
        require(msg.sender != loan.borrower, "You cannot loan yourself");
        require(
            block.timestamp < loan.loaningTimeEndTimestamp,
            "Loan open time ended"
        );
        loan.borrower.transfer(loan.amount);
        //Duration is in minutes for testing purpose
        loan.loanDurationEndTimestamp =
            block.timestamp +
            (loan.loanDuration * 1 minutes);
        loan.lender = payable(msg.sender);
        loan.status = Status.Loaned;
        emit loaned(loan.borrower, loan.lender, _loanId, loan.amount);
    }

    //If no one lends money in the particular window, users can close the request and get their NFT back
    function closeBorrowRequest(uint256 _loanId)
        public
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
        emit requestClosed(msg.sender, _loanId);
    }

    //Function using which the borrower can return the money and get his NFT back
    function repayLoan(uint256 _loanId)
        public
        payable
        correctAmount(_loanId)
        onlyBorrower(_loanId)
        isLoaned(_loanId)
    {
        Loan storage loan = loanList[_loanId];
        require(
            loan.loanDurationEndTimestamp > block.timestamp,
            "Loan duration Ended"
        );
        loan.lender.transfer(loan.amount);
        IERC721(loan.nftAddress).transferFrom(
            address(this),
            msg.sender,
            loan.nftId
        );
        loan.status = Status.Closed;
        emit loanRepayed(msg.sender, loan.lender, _loanId, loan.amount);
    }

    //If the borrower fails to pay back the money, after the loan duration ends, the nft is transfered the lender
    function ceaseNft(uint256 _loanId) public isLoaned(_loanId) {
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
        emit nftCeased(loan.borrower, loan.lender, _loanId);
    }

    //View funciton that returns the required details of the loan
    function getDetails(uint256 _loanId)
        public
        view
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
