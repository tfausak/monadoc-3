{-

# monadoc #

i've been writing this more or less in a straight line. i think ultimately the
whole thing should be scrapped and rewritten from the ground up. should that
happen, i need to be sure to keep the sqlite database around. it's got the
package index, every cabal file, and all package tarballs in it. it's possible
to download all that from hackage again, but there's no point.

## notes ##

- as on 2020-01-26, on my desktop, simply walking through all the package
  tarballs takes a little less than 4 minutes.

- as of 2020-01-24, the hackage package index has about:
  - 134k unique name-version-revision
  - 108k unique name-version
  - 15k unique name
  - 12gb of content (every package tarball compressed separately)

- an empty preferred version file cannot be parsed by cabal. but it means that
  the previous constraint is no longer valid. for example if you first got
  "pkg > 1" then you got an empty string, any version of "pkg" is good. look at
  the "lzma" package for an example.

- the json files in the index provide signature information about the cabal
  files. in other words, you can use them to make sure that the package files
  haven't been tampered with. since we're connecting to hackage over https,
  we're not worried about that. if it becomes necessary to check signatures,
  it would be useful to review the hackage-security repo.

- there isn't a good way to uniquely identify packages. you would think the
  name and version would be enough, but unfortunately revisions exist.
  revisions are nominally numbered, but hackage doesn't give you their number.
  (the x-revision field cannot be trusted.) the only way to come up with the
  number is to count how many times you've seen that package (name and version)
  so far.

  note that it's possible (although extremely unlikely) for the entire index to
  be rebuilt from scratch (aka "rebased"), presumably when something is
  deleted. in those situations it appears technically possible for a revision
  to be deleted, which could cause an otherwise unique identifier (name and
  version and revision) to either refer to something else or go away entirely.
  because of this, uniquely identifying packages by their hash is the only
  reasonable thing to do.

  except ... you can't do that either. sometimes revisions are byte-for-byte
  identical to the previous revision. so not even the package hash is
  guaranteed to be unique! https://github.com/haskell/hackage-server/issues/779

- some packages have been deleted (their tarballs are no longer available) but
  the package description remains in the index. for these packages we pretend
  as though they do have a tarball but it's empty.
  https://github.com/haskell-infra/hackage-trustees/issues/132

- similar to the 410 (gone) responses, some packages respond with 451
  (unavailable for legal reasons). the fix is the same.
  https://github.com/haskell/hackage-server/issues/436

- some packages are available but hackage refuses to serve the tarball because
  it's invalid. until a fix is rolled out, the only thing we can do is pretend
  that it's got an empty tarball.
  https://github.com/haskell/hackage-server/issues/851

- distribution of tar entries as of 2020-01-25:
  - normal-file: 3990714
  - directory: 872987
  - other-entry-type-x: 537. they are like the 'g' type. they store extended
    file information, like access or modification times. i think they can be
    ignored.

  - other-entry-type-L: 412. all with the path ".\.\@LongLink". this is used by
    the non-standard gnu tar to represent long path names. the standard ustar
    tar format puts a limit of 100 characters on the length of file names. the
    right thing to do is store the long file name and use it as the real file
    name for the next entry.
    https://github.com/haskell/hackage-server/issues/171

  - other-entry-type-5: 239. their paths all end in trailing slashes and their
    contents are all empty. i think they can be treated as directories.

  - other-entry-type-g: 81. every one seems to be a file called
    "pax_global_header", which is automatically created by git when making a
    tarball. more recently hackage strips these out on upload. they can be
    safely ignored. https://github.com/haskell/hackage-server/pull/190

  - symbolic-link: 24. they are spread over a few packages. none of them seem
    to be critical to building, so perhaps they can be safely ignored. the
    targets are sometimes tarball-relative paths like "debian\copyright". other
    times they are potentially dangerous relative paths like "..\ParseLib.hs".
    still other times they are complete nonsense like "matt@matt.local.13438".

  - hard-link: 16. they all come from the edit-lenses-demo-0.1 package. it
    seems like maybe something went wrong when making the tar? on my windows
    machine, i see an entry path like this:
      edit-lenses-demo-0.1\Data\Module\String.hs
    hard linking to:
      edit-lenses-demo-0.1/Data/Module/String.hs
    and some entries (including that one) are duplicated.
    https://github.com/haskell/hackage-server/issues/858

  - error-short-trailer: 1. since it happens at the end of the (otherwise
    valid) tarball, it can be ignored.
    https://github.com/haskell/hackage-server/issues/851

- some legacy tarballs contain entries that aren't prefixed with the package
  id. all such entries can safely be ignored.

- it is very common, even in recent tarballs, for normal files to reuse paths.
  from what i observed this normally happens when the file is executable. first
  there is an entry with non- executable permissions, then there is a duplicate
  entry with executable permissions set.

- since we aren't creating these entries on disk, we don't need to deal with
  directories. we only care about files.

- top 10 most common file extensions in package tarballs:
  - 2,015,312: hs
  -   187,078: mdwn
  -   130,018: cabal
  -    71,401: md
  -    63,842: h
  -    62,084: mml
  -    53,938: _comment
  -    48,062: xml
  -    47,804: yaml
  -    45,400: c

- among all the package tarballs, there are 3,992,312 files. of those, 977,050
  (24%) are unique. the total uncompressed size of all files in all package
  tarballs is 42,279,053,071 bytes (42 GB). for just the unique files, it's
  13,635,126,300 bytes (14 GB).

- build types (as of 2020-01-30):
  - 122,872: simple
  -  10,698: custom
  -     793: configure
  -      22: make

- doing extremely basic source file discovery works for a lot of packages, but
  not all. grabbing the hs-source-dirs and looking for *.hs or *.lhs files
  results in:
  - 1,297,475 found modules
  -   103,447 lost modules
  i need to dig into those lost modules to figure out why they can't be found.
  expanding that to include *.chs and *.hsc files gives:
  - 1,348,228 found
  -    52,694 lost
  maybe that's good enough? i probably won't be able to generate documentation
  for all the found ones anyway. i'm not planning on running the c pre
  processor or template haskell.

## todo ##

- [ ] add size to blobs

- [ ] make digests foreign keys to blobs

- [ ] we should probably track various file modification times. that way we can
  say when the index was updated, when various packages were uploaded, and so
  on. (how much smaller would the various tarballs be if all the times were set
  to the unix epoch?)
  for each entry in the index, the `entryTime` is set to when the package was
  uploaded, not when the tarball was created.

- [ ] we should probably track hackage metadata, like who uploaded a package
  and who can maintain it. unfortunately this information isn't in the index.
  we'll have to query separately for it.
  for each entry in the index, the `entryOwnership` -> `ownerName` is the
  hackage username of the uploader. maintainers are only available through the
  hackage api.

- [ ] what will happen in the unlikely scenario where hackage deletes a package
  from the index and rebases? will we continue to show the package? will we
  hide it? (same question for 410 and 451 responses on tarball requests for
  packages that used to work.) in other words, everything we're doing now is
  additive. we'll need some way to recognize that things have gone away.

- [x] technically the index is (usually) append only, and hackage supports
  range requests. we might be able to avoid re-downloading the entire index
  whenever anything changes. is that worthwhile?

  no, probably not. the whole index is relatively small: 82mb. since the whole
  index can be rebased, being defensive and always downloading the whole thing
  feels safer.

- [x] figure out why it takes so long to iterate over all package contents.
  also why the sqlite database size keeps growing.
  the answer was (a) it takes a long time to walk over 12 GB of data, and (b)
  vacuum the database you dummy.

- [x] now we have every package description and all the package contents. we
  can start parsing the package descriptions to get build information and use
  that to parse the package contents. parsing the descriptions looks like this:
    let Just gpd = parseGenericPackageDescriptionMaybe content

- [ ] get a list of all the components of each package. for example there could
  be the default library component, named libraries (since cabal ~~3~~ _2.2_),
  executables, test suites, and benchmarks. anything else?
  - condLibrary (pkg:lib)
  - condSubLibraries (pkg:lib:blah)
  - condForeignLibs (?)
  - condExecutables (pkg:exe:blah)
  - condTestSuites (pkg:test:blah)
  - condBenchmarks (pkg:bench:blah)

- [ ] for each library component, figure out which modules it exports. doing
  this may involve selecting flags and other build time constraints (like
  platform or operating system).
  if you ignore conditionals, this is easy. taking conditionals into account
  would require chasing down `condTreeComponents`. maybe it makes sense to
  build the superset of all possibly exposed modules?

- [ ] parsing the haskell sources is (way, way) more complicated. just getting
  ghc going shouldn't be too bad. this post is a good start:
  https://blog.shaynefletcher.org/2019/06/harvesting-annotations-from-ghc-parser.html
  however it's important to note that we're not trying to actually build
  the package. all we want to do is parse the source and extract comments.

  note that we'll want to use the latest ghc to parse source files, but it's
  not available on hackage. that means we'll need to upgrade our compiler so
  that we get the wired in package. (can you even reinstall the `ghc` package
  anyway?) https://github.com/haskell-infra/hackage-trustees/issues/240

-}

{-# language OverloadedStrings #-}

import Codec.Archive.Tar
import Codec.Archive.Tar.Entry
import Codec.Compression.GZip
import Control.Concurrent
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Exception
import Control.Monad
import Crypto.Hash
import Crypto.Hash.Algorithms
import Data.Aeson
import qualified Data.ByteArray as A
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import Data.Function ((&))
import qualified Data.Map.Strict as M
import Data.Maybe
import Data.List
import qualified Data.Set as S
import qualified Data.Text as T
import Data.Text.Encoding
import Data.Time
import Database.SQLite.Simple
import Distribution.ModuleName hiding (main)
import Distribution.PackageDescription.Parsec
import Distribution.Parsec
import Distribution.Pretty
import Distribution.Types.BuildInfo
import Distribution.Types.CondTree
import Distribution.Types.GenericPackageDescription
import Distribution.Types.Library
import Distribution.Types.PackageDescription
import Distribution.Types.PackageName
import Distribution.Types.PackageVersionConstraint
import Distribution.Types.Version
import Distribution.Types.VersionRange
import Lucid
import Network.HTTP.Client hiding (decompress, withConnection)
import Network.HTTP.Client.TLS
import Network.HTTP.Types
import Network.HTTP.Types.Header
import Network.Wai hiding (requestHeaders, responseHeaders, responseStatus)
import Network.Wai.Handler.Warp
import Network.Wai.Middleware.RequestLogger
import Numeric.Natural
import Prelude hiding (read)
import System.FilePath
import System.IO
import System.IO.Unsafe

main = withConnection "monadoc.sqlite" $ \ connection -> do
  puts "running migrations"
  execute_ connection "pragma journal_mode = wal"
  execute_ connection
    "create table if not exists blobs\
    \ (digest text primary key,\
    \ content blob not null)"
  execute_ connection
    "create table if not exists indices\
    \ (digest text not null,\
    \ etag text primary key,\
    \ updated_at datetime)"
  execute_ connection
    "create table if not exists preferred_versions\
    \ (package text primary key,\
    \ range text not null)"
  execute_ connection
    "create table if not exists packages\
    \ (name text not null,\
    \ version text not null,\
    \ revision int not null,\
    \ digest text not null,\
    \ unique (name, version, revision))"
  execute_ connection
    "create table if not exists tarballs\
    \ (name text not null,\
    \ version text not null,\
    \ digest text not null,\
    \ unique (name, version))"

  race_
    (worker connection)
    (server connection)

worker connection = do
  puts "starting worker"
  manager <- newTlsManager
  request <- parseRequest "https://hackage.haskell.org/01-index.tar.gz"
  forever $ do

    puts "starting worker loop"

    puts "pruning orphan blobs"
    digests <- do
      var <- newTVarIO (S.empty :: S.Set T.Text)
      rows <- query_ connection "select digest from indices"
      atomically . modifyTVar' var . S.union . S.fromList $ fmap fromOnly rows
      rows <- query_ connection "select digest from packages"
      atomically . modifyTVar' var . S.union . S.fromList $ fmap fromOnly rows
      rows <- query_ connection "select digest from tarballs"
      atomically . modifyTVar' var . S.union . S.fromList $ fmap fromOnly rows
      readTVarIO var
    fold_ connection "select digest from blobs" () $ \ () (Only digest) ->
      unless (S.member digest digests) $
        execute connection "delete from blobs where digest = ?" $ Only digest
    withTransaction connection $ execute_ connection "select 1"

    puts "getting package index"
    etag <- fmap (fmap fromOnly . listToMaybe) $ query_ connection
      "select etag from indices order by updated_at desc limit 1"
    response <- verboseHttp manager request
      { requestHeaders = [(hIfNoneMatch, fromMaybe mempty etag)] }

    puts "updating package index in database"
    indexContent <- case statusCode $ responseStatus response of
      304 -> do
        [Only digest] <- query_ connection
          "select digest from indices order by updated_at desc limit 1"
        [Only content] <- query connection
          "select content from blobs where digest = ?" $
          Only (digest :: String)
        pure content
      200 -> do
        let Just newEtag = lookup hETag $ responseHeaders response
        now <- getCurrentTime
        rows <- query connection
          "select digest from indices where etag != ?" $ Only newEtag
        let content = responseBody response
        let digest = hashWith SHA256 $ L.toStrict content
        execute connection
          "insert into blobs (digest, content) values (?, ?)\
          \ on conflict do nothing"
          (show digest, content)
        unless (null rows) $ execute connection
          "delete from blobs where digest in (?)"
          (fmap fromOnly rows :: [String])
        execute connection
          "insert into indices (digest, etag, updated_at)\
          \ values (?, ?, ?) on conflict (etag) do update\
          \ set updated_at = excluded.updated_at"
          ( show digest
          , newEtag
          , now
          )
        execute connection "delete from indices where etag != ?" $ Only newEtag
        pure content

    puts "processing package index"
    indexVar <- newTVarIO M.empty
    rangesVar <- newTVarIO M.empty
    foldEntries
      (\ entry action -> do
        case entryContent entry of
          NormalFile lazyContent _ ->
            let content = L.toStrict lazyContent
            in case splitDirectories $ entryPath entry of
              [package, "preferred-versions"] -> do
                range <- case simpleParsec . T.unpack $ decodeUtf8 content of
                  Nothing -> if B.null content
                    then pure anyVersion
                    else fail $ show (entryPath entry, content)
                  Just (PackageVersionConstraint _ range) -> pure range
                atomically . modifyTVar' rangesVar $ M.insert package range
              [package, version, path] -> case splitExtensions path of
                (file, ".json") ->
                  pure ()
                (file, ".cabal") -> do
                  let digest = hashWith SHA256 content
                  execute connection
                    "insert into blobs (digest, content) values (?, ?)\
                    \ on conflict do nothing"
                    (show digest, content)
                  let Just ver = simpleParsec version
                  let this = M.singleton (mkPackageName package) $
                        M.singleton (ver :: Version) [digest]
                  atomically . modifyTVar' indexVar $ \ index ->
                    M.unionWith (M.unionWith mappend) index this
        action)
      (pure ())
      throwIO
      . read
      $ decompress indexContent

    puts "updating preferred version ranges"
    ranges <- readTVarIO rangesVar
    forM_ (M.toList ranges) $ \ (package, range) -> do
      execute connection
        "insert into preferred_versions\
        \ (package, range) values (?, ?)\
        \ on conflict (package) do update set range = excluded.range"
        (package, prettyShow range)

    puts "updating package descriptions in the database"
    index <- readTVarIO indexVar
    forM_ (M.toList index) $ \ (package, versions) ->
      forM_ (M.toList versions) $ \ (version, revisions) ->
        forM_ (zip [0 ..] revisions) $ \ (revision, digest) -> do
          rows <- query connection
            "select digest from packages where\
            \ name = ? and version = ? and revision = ?"
            ( unPackageName package
            , prettyShow version
            , revision :: Int
            )
          case rows of
            [Only previousDigest] | previousDigest /= show digest -> fail $
              "revision changed! " <> show (package, version, revision, digest)
            _ -> pure ()
          execute connection
            "insert into packages (name, version, revision, digest)\
            \ values (?, ?, ?, ?)\
            \ on conflict (name, version, revision) do nothing"
            ( unPackageName package
            , prettyShow version
            , revision
            , show digest
            )

    puts "getting package tarballs"
    pkgIds <- query_ connection
      "select name, version from packages order by name asc, version asc"
    forM_ pkgIds $ \ (name, version) -> do
      tarballs <- query connection
        "select digest from tarballs where name = ? and version = ? limit 1"
        (name, version)
      when (null (tarballs :: [Only String])) $ do
        let pkgId = name <> "-" <> version
        request <- parseRequest $ "https://hackage.haskell.org/package/"
          <> pkgId <> "/" <> pkgId <> ".tar.gz"
        response <- verboseHttp manager request
        let emptyTarball = L.toStrict . compress $ write []
        content <- case statusCode $ responseStatus response of
          200 -> pure . L.toStrict $ responseBody response
          410 -> pure emptyTarball
          451 -> pure emptyTarball
          500 -> pure emptyTarball
        let digest = show $ hashWith SHA256 content
        execute connection
          "insert into blobs (digest, content) values (?, ?)\
          \ on conflict do nothing"
          (digest, content)
        execute connection
          "insert into tarballs (name, version, digest) values (?, ?, ?)"
          (name, version, digest)

    puts "analyzing package tarballs"
    rows <- query_ connection
      "select name, version, revision, digest from packages\
      \ order by name asc, version asc, revision asc\
      \ /* limit 100 /* TODO */"
    foundVar <- newTVarIO (0 :: Natural)
    lostVar <- newTVarIO (0 :: Natural)
    forM_ rows $ \ (name, version, revision, packageDigest) -> do
      [Only package] <- query connection
        "select content from blobs where digest = ?" $ Only packageDigest
      [Only tarballDigest] <- query connection
        "select digest from tarballs where name = ? and version = ?"
        (name, version)
      [Only tarball] <- query connection
        "select content from blobs where digest = ?" $ Only tarballDigest
      let
        _ = name :: String
        _ = version :: String
        _ = revision :: Int
        _ = packageDigest :: String
        _ = tarballDigest :: String
        packageId = name ++ "-" ++ version
        Just gpd = parseGenericPackageDescriptionMaybe package
      nameVar <- newEmptyTMVarIO
      filesVar <- newTVarIO S.empty
      foldEntries
        (\ entry action -> do
          let path = entryPath entry
          if isPrefixOf (packageId ++ [pathSeparator]) path
            || path == packageId
            || path == joinPath [".", ".", "@LongLink"]
            then do
              case entryContent entry of
                Directory -> pure ()
                HardLink _ -> pure ()
                NormalFile content _ -> do
                  maybeName <- atomically $ tryTakeTMVar nameVar
                  let fullPath = fromMaybe path maybeName
                  atomically . modifyTVar' filesVar $ S.insert fullPath
                OtherEntryType '5' _ _ -> pure ()
                OtherEntryType 'g' _ _ -> pure ()
                OtherEntryType 'L' content _ -> do
                  succeeded <- atomically
                    . tryPutTMVar nameVar
                    . T.unpack
                    . decodeUtf8
                    $ L.toStrict content
                  unless succeeded . fail $ unwords
                    [name, version, "long link mishap", path]
                OtherEntryType 'x' _ _ -> pure ()
                SymbolicLink _ -> pure ()
                _ -> fail $ "bad entry " ++ show (name, version, entry)
            else unless
              ( isPrefixOf (combine "." "PaxHeaders.") path
              || path == "pax_global_header"
              || path == combine "." ("._" ++ packageId)
              || path == (packageId ++ ".sig")
              ) . fail $ unwords [name, version, "bad path", show path]
          action)
        (pure ())
        (\ problem -> case problem of
          ShortTrailer -> pure ()
          _ -> throwIO problem)
        . read
        $ decompress tarball
      maybeName <- atomically $ tryTakeTMVar nameVar
      when (isJust maybeName) . fail $ unwords
        [name, version, "long link mishap"]

      case condLibrary gpd of
        Nothing -> pure ()
        Just lib -> do
          files <- readTVarIO filesVar
          let
            dirs = fmap (combine packageId) $
              case hsSourceDirs . libBuildInfo $ condTreeData lib of
                [] -> ["."]
                xs -> xs
            exts = [ "hs", "lhs", "hsc", "chs" ]
            (found, lost) = partition
              (\ mod -> any (flip S.member files)
                . fmap normalise
                . concatMap (\ f -> fmap (flip combine f) dirs)
                $ fmap (addExtension $ toFilePath mod) exts)
              . exposedModules $ condTreeData lib
          atomically $ do
            modifyTVar' foundVar (+ fromIntegral (length found))
            modifyTVar' lostVar (+ fromIntegral (length lost))
    found <- readTVarIO foundVar
    lost <- readTVarIO lostVar
    print ("found", found)
    print ("lost", lost)

    puts "worker finished, waiting one minute"
    threadDelay 60000000

server connection = do
  puts "starting server"
  run 8080 . logStdoutDev $ \ request respond -> do
    [Only now] <- query_ connection "select datetime('now')"
    respond . responseLBS ok200 [] . renderBS . doctypehtml_ $ do
      head_ $ do
        title_ "Monadoc"
      body_ $ do
        h1_ "Monadoc"
        p_ . toHtml $
          formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" (now :: UTCTime)

puts message = do
  atomically $ takeTMVar putsVar
  now <- getCurrentTime
  putStrLn $
    formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%3QZ " now <> message
  atomically $ putTMVar putsVar ()

putsVar = unsafePerformIO $ newTMVarIO ()

verboseHttp manager request = do
  let method_ = T.unpack . decodeUtf8 $ method request
  let uri_ = show $ getUri request
  puts $ method_ <> " " <> uri_
  response <- httpLbs request manager
  let status_ = show . statusCode $ responseStatus response
  puts $ status_ <> " " <> method_ <> " " <> uri_
  pure response
