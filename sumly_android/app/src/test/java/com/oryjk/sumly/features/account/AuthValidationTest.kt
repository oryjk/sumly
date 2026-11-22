package com.oryjk.sumly.features.account

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthValidationTest {
    @Test
    fun passwordLengthIsMeasuredInUnicodeCodePointsWithoutTrimming() {
        assertTrue(AuthValidation.validPassword(" " + "𐐀".repeat(10) + " "))
        assertTrue(AuthValidation.validPassword("𐐀".repeat(128)))
        assertFalse(AuthValidation.validPassword("𐐀".repeat(11)))
        assertFalse(AuthValidation.validPassword("𐐀".repeat(129)))
    }

    @Test
    fun emailRetainsDotAndPlusAddressing() {
        assertEquals("a.b+test@example.com", AuthValidation.email(" A.B+Test@Example.COM "))
        assertFalse(AuthValidation.validEmail("a @example.com"))
    }

    @Test
    fun phoneAcceptsOnlyMainlandChinaAndCodeUsesAsciiDigits() {
        assertEquals("+8613800138000", AuthValidation.phone(" 13800138000 "))
        assertEquals("+8613800138000", AuthValidation.phone("+8613800138000"))
        assertNull(AuthValidation.phone("+85212345678"))
        assertFalse(AuthValidation.validCode("１２３４５６"))
    }
}
