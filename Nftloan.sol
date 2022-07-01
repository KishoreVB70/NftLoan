//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/*
Todo
    1)Test if all the current functionality works accordingly
    2)Add events (Actually learn how to use events today itself)
    3)Contemplate of adding the concept of interest (Will add it for the celo submission)
    4)Add hell load of comments
*/

contract NftLoan{

    struct Loan{
        //Amount in wei
        uint amount;
        uint nftId;
        uint loaningTimeEndTimestamp;
        uint loanDuration;
        uint loanDurationEndTimestamp;
        address nftAddress;
        address payable borrower;
        address payable lender;
        Status status;
    }

    enum Status{
        Open,
        Loaned,
        Closed
    }

    mapping(uint => Loan) loanList;

    uint public loanId;

    //Modifiers

    modifier correctAmount(uint _loanId){
        require(msg.value ==  loanList[_loanId].amount, "Send the correct amount");
        _;
    }

    modifier onlyBorrower(uint _loanId){
        require(msg.sender == loanList[_loanId].borrower, "Only the borrower can access this function");
        _;
    }

    modifier isOpen(uint _loanId){
        require(loanList[_loanId].status == Status.Open, "Loan is not Open");
        _;
    }

    modifier isLoaned(uint _loanId){
        require(loanList[_loanId].status == Status.Loaned, "The loan is not in loaned state");
        _;
    }

    //Events
    event newLoan(address borrower, uint indexed loanId);

    event loaned(address borrower, address lender, uint indexed loanId, uint amount);

    event requestClosed(address borrower, uint indexed loanId);

    event loanRepayed(address borrower, address lender, uint indexed loanId, uint amount );

    event nftCeased(address borrower, address  lender, uint indexed loanId);

//----------------------------------------------------------------------------------------------------------------------
    
    //Function using which the users can make a loan request
    function askForLoan(uint _nftId, address _nft, uint _amount, uint _loanClosingDuration, uint _loanDuration) public{
        IERC721(_nft).transferFrom(msg.sender, address(this), _nftId);
        uint loanClosingTimeStamp = block.timestamp + _loanClosingDuration * 60;
        loanList[loanId] = Loan(_amount,  _nftId, loanClosingTimeStamp, _loanDuration, 0 , _nft,  payable(msg.sender), payable(address(0)), Status.Open );
        emit newLoan(msg.sender, loanId);
        loanId++;
    }

    //Other users can view the request details and use this function to lend money
    function lendMoney(uint _loanId) public payable correctAmount(_loanId) isOpen(_loanId){
        Loan storage loan = loanList[_loanId];
        require(msg.sender != loan.borrower, "You cannot loan yourself");
        require(block.timestamp < loan.loaningTimeEndTimestamp, "Loan open time ended");
        loan.borrower.transfer(loan.amount);
        loan.loanDurationEndTimestamp = block.timestamp + loan.loanDuration * 60;
        loan.lender = payable(msg.sender);
        loan.status = Status.Loaned;
        emit loaned(loan.borrower, loan.lender, _loanId, loan.amount);
    }

    //If no one lends money in the particular window, users can close the request and get their NFT back
    function closeBorrowRequest(uint _loanId) public onlyBorrower(_loanId) isOpen(_loanId){
        Loan storage loan = loanList[_loanId];
        require(block.timestamp > loan.loaningTimeEndTimestamp, "The loan is still open");
        IERC721(loan.nftAddress).transferFrom(address(this), msg.sender, loan.nftId);
        loan.status = Status.Closed;
        emit requestClosed(msg.sender, _loanId);
    }
    
    //Function using which the borrower can return the money and get his NFT back
    function repayLoan(uint _loanId) public payable correctAmount(_loanId) onlyBorrower(_loanId) isLoaned(_loanId){
        Loan storage loan = loanList[_loanId];
        require(loan.loanDurationEndTimestamp > block.timestamp, "Loan duration Ended");
        loan.lender.transfer(loan.amount);
        IERC721(loan.nftAddress).transferFrom(address(this), msg.sender, loan.nftId);
        loan.status = Status.Closed;
        emit loanRepayed(msg.sender, loan.lender, _loanId, loan.amount);
    }

    //If the borrower fails to pay back the money, after the loan duration ends, the nft is transfered the lender
    function ceaseNft(uint _loanId) public isLoaned(_loanId){
        Loan storage loan = loanList[_loanId];
        require(msg.sender == loan.lender, "Only the lender can cease the NFT");
        require(loan.loanDurationEndTimestamp < block.timestamp, "Loan duration not over");
        IERC721(loan.nftAddress).transferFrom(address(this), msg.sender, loan.nftId);
        loan.status = Status.Closed;
        emit nftCeased(loan.borrower, loan.lender, _loanId);
    }
    
    //View funciton that returns the required details of the loan
    function getDetails(uint _loanId) public view returns(uint amount, uint nftId,uint loaningTimeEndTimestamp, uint loanDuration, uint loanDurationEndTimestamp, address nftAddress, address payable borrowerAddress, address payable lenderAddress, Status status){
        Loan storage loan = loanList[_loanId];
        return(
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