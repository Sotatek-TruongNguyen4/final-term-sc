// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./libraries/Util.sol";
import { Events } from "contracts/libraries/Events.sol";
import { Constants } from "contracts/libraries/Constants.sol";

contract NFTMarketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable, IERC1155Receiver, IERC721Receiver {
    using SafeERC20 for IERC20;
    using Util for address;

    // Constants
    uint8 public constant MAX_TAX = 100;

    // States
    uint8 public sellTax;
    uint8 public buyTax;
    address public treasury;
    mapping(address => bool) public blacklist;

    struct Listing {
        uint256 price;
        uint256 erc1155Quantity;
        address paymentToken;
        address seller;
        address nftAddress;
        uint256 tokenId;
        bool isSold;
    }

    struct Auction {
        address seller;
        address nftAddress;
        address priceToken;
        uint256 tokenId;
        uint256 erc1155Quantity;
        uint256 floorPrice;
        uint256 startAuction;
        uint256 endAuction;
        uint256 bidIncrement;
        uint256 bidCount;
        uint256 currentBidPrice;
        address payable currentBidOwner;
        bool isEnded;
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => uint256)) public bids;
    mapping(uint256 => Listing) public directSales;
    mapping(address => mapping(address => uint256)) private pendingWithdrawals;
    uint256 private auctionId;
    uint256 private listingId;

    // Modifiers
    modifier onlyWhitelisted() {
    if (blacklist[_msgSender()]) revert("User is blacklisted");
    _;
    }

    modifier validPrice(uint256 _price) {
        if (_price == 0) revert("Invalid price");
        _;
    }

    modifier auctionExists(uint256 _auctionId) {
        if (auctions[_auctionId].floorPrice == 0) revert("Auction does not exist");
        _;
    }

    modifier onlyAuctionCreator(uint256 _auctionId) {
        if (auctions[_auctionId].seller != _msgSender()) revert("Only auction creator");
        _;
    }

    modifier auctionIsLive(uint256 _auctionId) {
        if (auctions[_auctionId].endAuction < block.timestamp || auctions[_auctionId].isEnded) {
            revert("Auction is not live");
        }
        _;
    }

    modifier validErc1155Quantity(address nftAddress, uint256 _quantity) {
        if (nftAddress.isERC1155() && _quantity == 0) revert("Invalid ERC1155 quantity");
        _;
    }

    modifier saleExists(uint256 _saleId) {
        if (directSales[_saleId].price == 0) revert("Sale does not exist");
        _;
    }

    modifier onlySeller(uint256 _saleId) {
        if (directSales[_saleId].seller != _msgSender()) revert("Only seller");
        _;
    }

    modifier itemIsAvailable(uint256 _saleId) {
        if (directSales[_saleId].isSold) revert("Item is sold");
        _;
    }
    // Constructor and Initializer

    /**
     * @dev Disables initializers to prevent misuse.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with a treasury address and default taxes.
     * @param _treasury Address of the treasury where tax fees will be sent.
     */
    function initialize(address _treasury) public initializer {
        sellTax = 25;
        buyTax = 25;
        treasury = _treasury;
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
    }

    // Internal Functions

    /**
     * @dev Calculates the bid price from the amount placed by the user, considering the buy tax.
     * @param _userPlacedAmount Amount placed by the user.
     * @return The bid price after deducting the buy tax.
     */
    function calculateBidPriceFromUserAmount(uint256 _userPlacedAmount) internal view returns (uint256) {
        return (_userPlacedAmount * Constants.TAX_BASE) / (Constants.TAX_BASE + buyTax);
    }

    /**
     * @dev Calculates the sell tax fee for a given price.
     * @param _price Price of the item.
     * @return The sell tax fee.
     */
    function calculateSellTaxFee(uint256 _price) internal view returns (uint256) {
        return (_price * sellTax) / Constants.TAX_BASE;
    }

    /**
     * @dev Calculates the buy tax fee for a given price.
     * @param _price Price of the item.
     * @return The buy tax fee.
     */
    function calculateBuyTaxFee(uint256 _price) internal view returns (uint256) {
        return (_price * buyTax) / Constants.TAX_BASE;
    }

    /**
     * @dev Delists an NFT from an auction.
     * @param _auctionId ID of the auction to delist.
     */
    function delistAuctionedNFT(uint256 _auctionId) internal {
        Auction memory auction = auctions[_auctionId];
        if (auction.nftAddress.isERC721()) {
            IERC721(auction.nftAddress).safeTransferFrom(address(this), _msgSender(), auction.tokenId);
        } else {
            IERC1155(auction.nftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                auction.tokenId,
                auction.erc1155Quantity,
                ""
            );
        }
    }

    // Tax Functions

    /**
     * @dev Sets the sell and buy tax fees.
     * @param _sellTax New sell tax fee (in percentage points).
     * @param _buyTax New buy tax fee (in percentage points).
     */
    function updateTaxFees(uint8 _sellTax, uint8 _buyTax) external onlyOwner {
        require(_sellTax <= MAX_TAX, "Invalid sell tax");
        require(_buyTax <= MAX_TAX, "Invalid buy tax");

        sellTax = _sellTax;
        buyTax = _buyTax;

        emit Events.TaxChanged(_sellTax, _buyTax);
    }

    // Ban/Unban Functions

    /**
     * @dev Adds a user to the blacklist.
     * @param user Address of the user to ban.
     */
    function banUser(address user) external onlyOwner {
        blacklist[user] = true;
        emit Events.UserBanned(user);
    }

    /**
     * @dev Removes a user from the blacklist.
     * @param user Address of the user to unban.
     */
    function unbanUser(address user) external onlyOwner {
        delete blacklist[user];
        emit Events.UserUnbanned(user);
    }

    // Auction Functions

    /**
     * @dev Creates a new auction.
     * @param _priceToken Address of the token to be used for bids.
     * @param _nftAddress Address of the NFT contract.
     * @param _tokenId ID of the token to auction.
     * @param _floorPrice Minimum price for the auction.
     * @param _startAuction Start time of the auction.
     * @param _endAuction End time of the auction.
     * @param _erc1155Quantity Quantity of ERC1155 tokens (set to 0 for ERC721).
     * @param _bidIncrement Minimum increment for bids.
     */
    function createAuction(
        address _priceToken,
        address _nftAddress,
        uint256 _tokenId,
        uint256 _floorPrice,
        uint256 _startAuction,
        uint256 _endAuction,
        uint256 _erc1155Quantity,
        uint256 _bidIncrement
    ) external onlyWhitelisted validPrice(_floorPrice) validErc1155Quantity(_nftAddress, _erc1155Quantity) {
        require(_startAuction > block.timestamp, "Start time must be in the future");
        require(_startAuction < _endAuction, "Start time must be before end time");
        require(_bidIncrement > 0, "Bid increment must be above zero");

        if (_nftAddress.isERC721()) {
            IERC721(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId);
        } else {
            IERC1155(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId, _erc1155Quantity, "");
        }

        auctions[auctionId++] = Auction(
            _msgSender(),
            _nftAddress,
            _priceToken,
            _tokenId,
            _erc1155Quantity,
            _floorPrice,
            _startAuction,
            _endAuction,
            _bidIncrement,
            0,
            0,
            payable(address(0)),
            false
        );

        emit Events.AuctionCreated(
            _msgSender(),
            _priceToken,
            _nftAddress,
            _tokenId,
            _floorPrice,
            _startAuction,
            _endAuction,
            _erc1155Quantity,
            _bidIncrement
        );
    }

    /**
     * @dev Places a bid on an active auction.
     * @param _auctionId ID of the auction to bid on.
     * @param _bidAmount Amount of the bid.
     */
    function placeBid(uint256 _auctionId, uint256 _bidAmount) external payable onlyWhitelisted auctionExists(_auctionId) auctionIsLive(_auctionId) {
        Auction storage auction = auctions[_auctionId];

        uint256 bidAmount = auction.priceToken.isETH() ? msg.value : _bidAmount;
        uint256 userBid = calculateBidPriceFromUserAmount(bidAmount);

        require(userBid > auction.currentBidPrice, "Bid must be higher than current bid");
        require(userBid >= auction.floorPrice, "Bid must be higher than floor price");
        require(userBid >= auction.currentBidPrice + auction.bidIncrement, "Bid increment too low");

        if (!auction.priceToken.isETH()) {
            IERC20(auction.priceToken).safeTransferFrom(_msgSender(), address(this), bidAmount);
        }

        if (auction.bidCount > 0) {
            bids[_auctionId][auction.currentBidOwner] += auction.currentBidPrice;
        }

        auction.currentBidOwner = payable(_msgSender());
        auction.currentBidPrice = userBid;
        auction.bidCount++;

        emit Events.BidPlaced(_auctionId, _msgSender(), userBid);
    }

    /**
     * @dev Withdraws a bid from an auction.
     * @param _auctionId ID of the auction to withdraw the bid from.
     */
    function withdrawBid(uint256 _auctionId) external nonReentrant {
        uint256 withdrawalAmount = bids[_auctionId][_msgSender()];
        require(withdrawalAmount > 0, "No bid to withdraw");

        bids[_auctionId][_msgSender()] = 0;

        Auction storage auction = auctions[_auctionId];
        if (auction.priceToken.isETH()) {
            (bool success, ) = payable(_msgSender()).call{ value: withdrawalAmount }("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(auction.priceToken).safeTransfer(_msgSender(), withdrawalAmount);
        }

        emit Events.BidWithdrawn(_auctionId, _msgSender(), withdrawalAmount);
    }

    /**
     * @dev Ends an auction and transfers the NFT to the highest bidder.
     * @param _auctionId ID of the auction to end.
     */
    function endAuction(uint256 _auctionId) external onlyWhitelisted auctionExists(_auctionId) auctionIsLive(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(block.timestamp >= auction.endAuction, "Auction not yet ended");

        uint256 highestBid = auction.currentBidPrice;
        uint256 taxFee = calculateSellTaxFee(highestBid);

        pendingWithdrawals[auction.priceToken][auction.seller] += highestBid - taxFee;
        pendingWithdrawals[auction.priceToken][treasury] += taxFee;

        if (auction.nftAddress.isERC721()) {
            IERC721(auction.nftAddress).safeTransferFrom(address(this), auction.currentBidOwner, auction.tokenId);
        } else {
            IERC1155(auction.nftAddress).safeTransferFrom(
                address(this),
                auction.currentBidOwner,
                auction.tokenId,
                auction.erc1155Quantity,
                ""
            );
        }

        auction.isEnded = true;
        emit Events.AuctionEnded(_auctionId, auction.currentBidOwner, auction.currentBidPrice);
    }

    /**
     * @dev Withdraws an active auction with no bids.
     * @param _auctionId ID of the auction to withdraw.
     */
    function withdrawActiveAuction(uint256 _auctionId) external onlyWhitelisted onlyAuctionCreator(_auctionId) auctionExists(_auctionId) auctionIsLive(_auctionId) {
        require(auctions[_auctionId].bidCount == 0, "Bids already placed");
        delistAuctionedNFT(_auctionId);
        delete auctions[_auctionId];
        emit Events.AuctionWithdrawn(_auctionId);
    }

    // Sales Functions

    /**
     * @dev Creates a direct sale listing for an NFT.
     * @param _paymentToken Address of the token to be used for payment.
     * @param _nftAddress Address of the NFT contract.
     * @param _tokenId ID of the token to list for sale.
     * @param _price Price of the token.
     * @param _erc1155Quantity Quantity of ERC1155 tokens (set to 0 for ERC721).
     */
    function createDirectSale(
        address _paymentToken,
        address _nftAddress,
        uint256 _tokenId,
        uint256 _price,
        uint256 _erc1155Quantity
    ) external onlyWhitelisted validPrice(_price) validErc1155Quantity(_nftAddress, _erc1155Quantity) {
        if (_nftAddress.isERC721()) {
            IERC721(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId);
        } else {
            IERC1155(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId, _erc1155Quantity, "");
        }

        directSales[listingId++] = Listing(
            _price,
            _erc1155Quantity,
            _paymentToken,
            _msgSender(),
            _nftAddress,
            _tokenId,
            false
        );

        emit Events.SaleCreated(
            _msgSender(),
            _paymentToken,
            _nftAddress,
            _tokenId,
            _price,
            _erc1155Quantity
        );
    }

    /**
     * @dev Purchases an NFT from a direct sale listing.
     * @param _saleId ID of the sale listing to buy from.
     * @param _price Offered price for the NFT.
     */
    function purchaseFromSale(uint256 _saleId, uint256 _price) external payable onlyWhitelisted saleExists(_saleId) itemIsAvailable(_saleId) {
        Listing storage listing = directSales[_saleId];

        uint256 priceFromUser = listing.paymentToken.isETH() ? msg.value : _price;
        uint256 priceAfterBuyTax = calculateBidPriceFromUserAmount(priceFromUser);

        require(priceAfterBuyTax == listing.price, "Invalid payment amount");

        uint256 sellTaxFee = calculateSellTaxFee(priceAfterBuyTax);
        pendingWithdrawals[listing.paymentToken][listing.seller] += priceAfterBuyTax - sellTaxFee;
        pendingWithdrawals[listing.paymentToken][treasury] += sellTaxFee;

        if (!listing.paymentToken.isETH()) {
            IERC20(listing.paymentToken).safeTransferFrom(_msgSender(), address(this), priceFromUser);
        }

        if (listing.nftAddress.isERC721()) {
            IERC721(listing.nftAddress).safeTransferFrom(address(this), _msgSender(), listing.tokenId);
        } else {
            IERC1155(listing.nftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                listing.tokenId,
                listing.erc1155Quantity,
                ""
            );
        }

        listing.isSold = true;
        emit Events.SaleCompleted(
            _saleId,
            _msgSender(),
            listing.seller,
            listing.nftAddress,
            listing.tokenId,
            priceAfterBuyTax
        );
    }

    /**
     * @dev Cancels a direct sale listing.
     * @param _saleId ID of the sale listing to cancel.
     */
    function cancelDirectSale(uint256 _saleId) external saleExists(_saleId) onlySeller(_saleId) itemIsAvailable(_saleId) {
        Listing storage listing = directSales[_saleId];

        if (listing.nftAddress.isERC721()) {
            IERC721(listing.nftAddress).safeTransferFrom(address(this), _msgSender(), listing.tokenId);
        } else {
            IERC1155(listing.nftAddress).safeTransferFrom(address(this), _msgSender(), listing.tokenId, listing.erc1155Quantity, "");
        }

        emit Events.SaleCanceled(_saleId);
        delete directSales[_saleId];
    }

    // Withdraw Functions

    /**
     * @dev Withdraws funds from pending withdrawals.
     * @param _tokenAddress Address of the token to withdraw.
     */
    function withdrawFunds(address _tokenAddress) external nonReentrant {
        uint256 amount = pendingWithdrawals[_tokenAddress][_msgSender()];
        require(amount > 0, "No funds to withdraw");
        pendingWithdrawals[_tokenAddress][_msgSender()] = 0;

        if (_tokenAddress.isETH()) {
            (bool success, ) = payable(_msgSender()).call{ value: amount }("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(_tokenAddress).safeTransfer(_msgSender(), amount);
        }
        emit Events.Withdrawal(_msgSender(), _tokenAddress, amount);
    }

    // Helper Functions

    /**
     * @dev Handles the receipt of a single ERC1155 token type.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Handles the receipt of mUtilple ERC1155 token types.
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Handles the receipt of an ERC721 token.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev Returns whether this contract implements the specified interface.
     * @param interfaceId ID of the interface.
     */
    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
