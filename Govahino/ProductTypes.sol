// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ProductTypes {
    struct OwnerInfo {
        bytes32 infoHash;     // هش اطلاعات شخصی
        uint256 timestamp;    // زمان ثبت
    }

    struct ProductDetails {
        string brand;
        string name;
        string description;
        string designer;
        uint256 manufactureDate;
    }

    struct ProductLimitation {
        bool isLimited;
        uint256 limitedNumber;
        uint256 totalLimited;
    }

    struct Product {
        string productId;
        ProductDetails details;
        ProductLimitation limitation;
        string[] certificates;
        string[] features;
        string[] images;
        uint256 ownerHistoryCount;  // تعداد مالکان
    }

    // ساختار جدید برای پارامترهای ثبت محصول
    struct RegistrationParams {
        string productId;
        ProductDetails details;
        ProductLimitation limitation;
        string[] certificates;
        string[] features;
        string[] images;
    }
}