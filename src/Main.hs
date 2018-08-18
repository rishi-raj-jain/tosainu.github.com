{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Monad
import           Data.Char
import           Data.Foldable          (fold)
import           Data.List              (find)
import           Hakyll
import           Hakyll.Web.Sass
import           Skylighting            (pygments, styleToCss)
import           System.FilePath
import qualified Text.HTML.TagSoup      as TS
import           Text.Pandoc.Extensions
import           Text.Pandoc.Options

import           Archives
import           Compiler
import           FontAwesome
import           LocalTime
import           TagField
import           Template

main :: IO ()
main = hakyllWith hakyllConfig $ do
  faIcons <- fold <$> preprocess loadFontAwesomeIcons

  -- "entry/year/month/day/title/index.md"
  let entryPattern      = "entry/*/*/*/*/index.md"
      entryFilesPattern = "entry/*/*/*/*/**"

  let tagPagesPath tag = "entry" </> "tags" </> sanitizeTagName tag </> "index.html"
  tags <- buildTags entryPattern $ fromFilePath . tagPagesPath

  let archivesPagesPath (Yearly y)    = "entry" </> y </> "index.html"
      archivesPagesPath (Monthly y m) = "entry" </> y </> m </> "index.html"
  archives <- buildYearMonthArchives entryPattern $ fromFilePath . archivesPagesPath

  match entryPattern $ do
    route $ setExtension "html"
    compile $ do
      content <- saveSnapshot "content" =<< pandocCompilerWith readerOptions writerOptions

      let ctx = yearMonthArchiveField "archives" archives
             <> postContext tags

      flc    <- mapM load ["footer_left.html", "footer_center.html"]
      fr     <- applyLucidTemplate footerWidgetRightTemplate ctx =<< makeEmptyItem'
      footer <- applyLucidTemplate footerTemplate ctx
                  =<< makeItem (concatMap itemBody $ flc ++ [fr])

      applyLucidTemplate postTemplate ctx content
        >>= renderKaTeX
        >>= withItemBody (\item -> return $ item <> itemBody footer)
        >>= applyLucidTemplate defaultTemplate ctx
        >>= modifyExternalLinkAttributes
        >>= cleanIndexHtmls
        >>= renderFontAwesome faIcons

  match entryFilesPattern $ do
    route idRoute
    compile copyFileCompiler

  tagsRules tags $ \tag pat -> do
    tagPages <- let grouper = fmap (paginateEvery 5) . sortRecentFirst
                    makeId  = makePageIdentifier $ tagPagesPath tag
                in  buildPaginateWith grouper pat makeId
    paginateRules tagPages $ \num pat' -> do
      route idRoute
      compile $ do
        footer <- loadBody "footer.html"
        posts  <- recentFirst =<< loadAllSnapshots pat' "content"
        let ctx = listField "posts" postContext' (return posts)
               <> paginateContext tagPages num
               <> defaultContext
            postContext' = teaserField "teaser" "content" <> postContext tags
            siteContext' = constField "title" title <> siteContext
            title = "Tag archives: " ++ tag
        makeItem title
          >>= applyLucidTemplate entryListTemplate ctx
          >>= renderKaTeX
          >>= withItemBody (\item -> return $ item <> footer)
          >>= applyLucidTemplate defaultTemplate siteContext'
          >>= modifyExternalLinkAttributes
          >>= cleanIndexHtmls
          >>= renderFontAwesome faIcons

  archivesRules archives $ \key pat -> do
    archivesPages <- let grouper = fmap (paginateEvery 5) . sortRecentFirst
                         makeId  = makePageIdentifier $ archivesPagesPath key
                     in  buildPaginateWith grouper pat makeId
    paginateRules archivesPages $ \num pat' -> do
      route idRoute
      compile $ do
        posts  <- recentFirst =<< loadAllSnapshots pat' "content"
        let ctx = listField "posts" postContext' (return posts)
                <> paginateContext archivesPages num
                <> defaultContext
            postContext' = teaserField "teaser" "content" <> postContext tags
            siteContext' = constField "title" title
                         <> yearMonthArchiveField' "archives" archives (year key)
                         <> siteContext
            title = case key of Yearly  y   -> "Yearly archives: "  <> y
                                Monthly y m -> "Monthly archives: " <> y <> "/" <> m

        flc    <- mapM load ["footer_left.html", "footer_center.html"]
        fr     <- applyLucidTemplate footerWidgetRightTemplate siteContext' =<< makeEmptyItem'
        footer <- applyLucidTemplate footerTemplate siteContext
                    =<< makeItem (concatMap itemBody $ flc ++ [fr])

        makeItem title
          >>= applyLucidTemplate entryListTemplate ctx
          >>= renderKaTeX
          >>= withItemBody (\item -> return $ item <> itemBody footer)
          >>= applyLucidTemplate defaultTemplate siteContext'
          >>= modifyExternalLinkAttributes
          >>= cleanIndexHtmls
          >>= renderFontAwesome faIcons

  entries <- let grouper = fmap (paginateEvery 5) . sortRecentFirst
                 makeId  = makePageIdentifier "index.html"
             in  buildPaginateWith grouper entryPattern makeId
  paginateRules entries $ \num pat -> do
    route idRoute
    compile $ do
      footer <- loadBody "footer.html"
      posts  <- recentFirst =<< loadAllSnapshots pat "content"
      let ctx = listField "posts" postContext' (return posts)
             <> paginateContext entries num
             <> defaultContext
          postContext' = teaserField "teaser" "content" <> postContext tags
          siteContext' = constField "title" "" <> siteContext
      makeEmptyItem'
        >>= applyLucidTemplate entryListTemplate ctx
        >>= renderKaTeX
        >>= withItemBody (\item -> return $ item <> footer)
        >>= applyLucidTemplate defaultTemplate siteContext'
        >>= modifyExternalLinkAttributes
        >>= cleanIndexHtmls
        >>= renderFontAwesome faIcons

  -- precompiled footer and footer widgets
  create ["footer.html"] $
    compile $
      mapM loadBody ["footer_left.html", "footer_center.html", "footer_right.html"]
        >>= makeItem . concat
        >>= applyLucidTemplate footerTemplate siteContext

  create ["footer_left.html"] $
    compile $ do
      recent <- fmap (take 5) . recentFirst =<< loadAllSnapshots entryPattern "content"
      let ctx = listField "recent-posts" (postContext tags) (return recent)
             <> authorContext
      makeEmptyItem' >>= applyLucidTemplate footerWidgetLeftTemplate ctx

  create ["footer_center.html"] $
    compile $ do
      let ctx = allTagsListField "all-tags" tags
      makeEmptyItem' >>= applyLucidTemplate footerWidgetCenterTemplate ctx

  create ["footer_right.html"] $
    compile $ do
      let ctx = yearMonthArchiveField "archives" archives
      makeEmptyItem' >>= applyLucidTemplate footerWidgetRightTemplate ctx

  create ["feed.xml"] $ do
    route idRoute
    compile $ do
      let ctx = bodyField "description" <> postContext tags
      posts <- fmap (take 20) . recentFirst =<< loadAllSnapshots entryPattern "content"
      renderAtom atomFeedConfig ctx posts

  match "images/**/*.svg" $ do
    route idRoute
    compile $ optimizeSVGCompiler ["-p", "4"]

  match ("CNAME" .||. "favicon.ico" .||. "images/**") $ do
    route idRoute
    compile copyFileCompiler

  scssDependencies <- makePatternDependency "stylesheets/*/**.scss"
  match "stylesheets/*/**.scss" $ compile getResourceBody
  rulesExtraDependencies [scssDependencies] $
    match "stylesheets/*.scss" $ do
      route $ setExtension "css"
      compile $ fmap compressCss <$> sassCompiler

  match "stylesheets/*.css" $ do
    route   idRoute
    compile compressCssCompiler

  create ["stylesheets/highlight.css"] $ do
    route   idRoute
    compile $ makeItem $ compressCss $ styleToCss pygments

  match "node_modules/@fortawesome/fontawesome-svg-core/styles.css" $ do
    route $ constRoute "vendor/fontawesome/style.css"
    compile compressCssCompiler

  match ("node_modules/katex/dist/**" .&&. complement "**.js") $ do
    route $ gsubRoute "node_modules/katex/dist/" (const "vendor/katex/")
    compile copyFileCompiler

  match "node_modules/normalize.css/**" $ do
    route $ gsubRoute "node_modules/" (const "vendor/")
    compile copyFileCompiler

--- Contexts
postContext :: Tags -> Context String
postContext tags = localDateField   "date"          "%Y/%m/%d %R"
                <> tagsListField    "tags"          tags
                <> descriptionField "description"   150
                <> imageField       "image"
                <> siteContext
  where descriptionField key len = field key $ \_ ->
          take len . escapeHtml . concat . lines . itemBody <$> getResourceBody

        imageField key = field key $ \item ->
          case find isImageTag $ TS.parseTags $ itemBody item of
               Just t  -> return $ TS.fromAttrib "src" t
               Nothing -> return ""
        isImageTag (TS.TagOpen "img" _) = True
        isImageTag _                    = False

siteContext :: Context String
siteContext   = constField "lang"              "ja"
             <> constField "site-title"        "Tosainu Lab"
             <> constField "site-description"  "とさいぬのブログです"
             <> constField "site-url"          "https://blog.myon.info"
             <> constField "copyright"         "© 2011-2018 Tosainu."
             <> constField "google-analytics"  "UA-57978655-1"
             <> constField "disqus"            "tosainu"
             <> authorContext
             <> defaultContext

authorContext :: Context String
authorContext = constField "author-name"       "Tosainu"
             <> constField "author-profile"    "❤ Arch Linux, ごちうさ"
             <> constField "author-portfolio"  "https://myon.info"
             <> constField "author-avatar"     "/images/icon/cocoa.svg"
             <> constField "author-twitter"    "myon___"

--- Misc
sanitizeTagName :: String -> String
sanitizeTagName = map (\x -> if x == ' ' then '-' else toLower x) .
                  filter (liftM2 (||) isAlphaNum (`elem` [' ', '-', '_']))

makePageIdentifier :: FilePath -> PageNumber -> Identifier
makePageIdentifier p 1 = fromFilePath p
makePageIdentifier p n = fromFilePath $ takeDirectory' p </> "page" </> show n </> takeFileName p
  where takeDirectory' x = let x' = takeDirectory x in if x' == "." then "" else x'

makeEmptyItem :: Monoid a => Compiler (Item a)
makeEmptyItem = makeItem mempty

makeEmptyItem' :: Compiler (Item String)
makeEmptyItem' = makeEmptyItem

--- Configurations
hakyllConfig :: Configuration
hakyllConfig = defaultConfiguration
  { destinationDirectory = "build"
  , storeDirectory       = ".cache"
  , tmpDirectory         = ".cache/tmp"
  , previewHost          = "0.0.0.0"
  , previewPort          = 4567
  }

atomFeedConfig :: FeedConfiguration
atomFeedConfig = FeedConfiguration
  { feedTitle       = "Tosainu Lab"
  , feedDescription = "とさいぬのブログです"
  , feedAuthorName  = "Tosainu"
  , feedAuthorEmail = "tosainu.maple@gmail.com"
  , feedRoot        = "https://blog.myon.info"
  }

readerOptions :: ReaderOptions
readerOptions = defaultHakyllReaderOptions
  { readerExtensions = enableExtension  Ext_east_asian_line_breaks $
                       enableExtension  Ext_emoji $
                       disableExtension Ext_citations $
                       readerExtensions defaultHakyllReaderOptions
  }

writerOptions :: WriterOptions
writerOptions = defaultHakyllWriterOptions
  { writerHTMLMathMethod = KaTeX ""
  }
