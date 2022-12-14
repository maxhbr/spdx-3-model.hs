{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
import qualified Data.ByteString            as BS
import qualified Data.ByteString.Lazy       as BSL
import qualified Data.ByteString.Lazy.Char8 as B
import           Data.FileEmbed             (embedFile)
import           Data.Time.Format.ISO8601
import           System.Directory
import           System.FilePath
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck      as QC
import           Test.Tasty.SmallCheck      as SC

import           Data.Aeson                 (eitherDecode)
import           Data.Aeson.Encode.Pretty   (encodePretty)
import           Data.Either                (isRight)
import qualified Purl.Purl                  as Purl
import           SPDX3.From2
import           SPDX3.Model
import           SPDX3.Monad

mkExample' :: IO (Either String (SPDX ()))
mkExample' = do
    let actors = [Actor (Just "Some Actor") (Just PERSON), Actor (Just "This Tool") (Just TOOL)]
    created <- iso8601ParseM "2022-11-13T13:14:36.324980945Z"
    let creationInfo = mkCreationInfo actors created
    return . runSPDX creationInfo $ do

        a0 <- package (Just "urn:spdx:curl-7.50.3-1") def{_packageUrl = Purl.parsePurl "pkg:deb/debian/curl@7.50.3-1?arch=i386&distro=jessie" } def def{_elementName = Just "curl-7.50.3-1"}


        f0 <- file Nothing def def def{_elementName = Just "path/to/the/file/f0"}
        f1 <- file Nothing def def def{_elementName = Just "path/to/the/file/f1"}

        r0 <- relationship Nothing (RelationshipProperties CONTAINS (toRef a0) [toRef f0, f1] Nothing) def

        an0 <- annotation (Just "urn:spdx:Annotation0") (AnnotationProperties "some Annotation" (toRef a0)) def
        c1 <- bundle Nothing def def{_collectionElements = [an0]} def

        spdxDocument (Just "urn:spdx:Document" ) def def{_collectionElements = [a0, r0, f0, c1]} def{_elementName = Just "The Document"}

mkExample :: IO (SPDX ())
mkExample = do
    (Right result) <- mkExample'
    return result

spdxFileBS :: BSL.ByteString
spdxFileBS = BSL.fromStrict $(embedFile "spdx-tools-hs/spdx-spec/examples/SPDXJSONExample-v2.3.spdx.json")

spdxYamlFileBS :: BSL.ByteString
spdxYamlFileBS = BSL.fromStrict $(embedFile "spdx-tools-hs/spdx-spec/examples/SPDXYAMLExample-2.3.spdx.yaml")

otherSpdxYamlFileBS :: BSL.ByteString
otherSpdxYamlFileBS = BSL.fromStrict $(embedFile "spdx-tools-hs/test/data/document.spdx.yml")

testOutputFolder :: FilePath
testOutputFolder = "_testOut"

main :: IO ()
main = do
  createDirectoryIfMissing True testOutputFolder
  defaultMain tests

tests :: TestTree
tests = testGroup "Tests" [unitTests, testsOnExample, testsFrom2]

unitTests :: TestTree
unitTests = testGroup "Unit tests" [
  testGroup "ToJSON and FromJSON" [
      testCase "testExample" $ do
        example <- mkExample
        let encoded = encodePretty example
        B.writeFile (testOutputFolder </> "example" <.> ".spdx3.json") encoded
        let parsed = eitherDecode encoded :: Either String (SPDX ())
        let potentialParseError = case parsed of
                                    Right _  -> ""
                                    Left err -> err
        assertEqual "should succeed parsing testExample" "" potentialParseError
    ]
  ]
testsOnExample :: TestTree
testsOnExample = testGroup "tests on example" []
testsFrom2 :: TestTree
testsFrom2 = let
     bss = [ ("SPDXJSONExample-v2.3.spdx.json",spdxFileBS)
           , ("SPDXYAMLExample-2.3.spdx.yaml", spdxYamlFileBS)
           , ("document.spdx.yml", otherSpdxYamlFileBS)
           ]
  in testGroup "test conversation from 2" $ map (\(fn, bs) -> testCase ("parse BS for " ++ fn) $ do
        let result = convertBsDocument bs
        let potentialConvertError = case result of
                                Right _  -> ""
                                Left err -> err
        assertEqual ("should succeed conversion " ++ fn) "" potentialConvertError
        case result of
          Right success -> do
            let encoded = encodePretty success
            B.writeFile (testOutputFolder </> fn <.> ".spdx3.json") encoded
            let parsed = eitherDecode encoded :: Either String (SPDX ())
            let potentialParseError = case parsed of
                                        Right _  -> ""
                                        Left err -> err
            assertEqual ("should succeed parsing " ++ fn) "" potentialParseError
          Left _ -> pure ()
      ) bss
