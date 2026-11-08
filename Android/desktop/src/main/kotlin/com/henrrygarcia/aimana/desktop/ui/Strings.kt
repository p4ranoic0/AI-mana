package com.henrrygarcia.aimana.desktop.ui

import java.util.Locale
import java.util.PropertyResourceBundle
import java.util.ResourceBundle

/// UI text in en, es, pt-BR, fr, de and it (`strings/messages*.properties`, UTF-8).
class Strings(locale: Locale = Locale.getDefault()) {
    private val bundle: ResourceBundle = load(locale)
    val locale: Locale = locale
    operator fun get(key: String): String = bundle.getString(key)
    fun format(key: String, vararg args: Any?): String = String.format(bundle.locale, get(key), *args)

    companion object {
        private val control = object : ResourceBundle.Control() {
            override fun getFormats(baseName: String) = FORMAT_PROPERTIES
            override fun getFallbackLocale(baseName: String, locale: Locale): Locale? = null
            override fun newBundle(baseName: String, locale: Locale, format: String, loader: ClassLoader, reload: Boolean): ResourceBundle? {
                val name = toResourceName(toBundleName(baseName, locale), "properties")
                return loader.getResourceAsStream(name)?.use { PropertyResourceBundle(it.reader(Charsets.UTF_8)) }
            }
        }
        private fun load(locale: Locale) = ResourceBundle.getBundle("strings/messages", locale, Strings::class.java.classLoader, control)
        /// The keys a language defines itself (tests: every language is complete).
        fun keys(locale: Locale): Set<String> =
            if (locale.language == "en") load(Locale.ROOT).keySet() else load(locale).let { b -> b.keySet().filter { b.handleKeySetContains(it) }.toSet() }
        private fun ResourceBundle.handleKeySetContains(key: String) = (this as? PropertyResourceBundle)?.handleGetObject(key) != null
    }
}
