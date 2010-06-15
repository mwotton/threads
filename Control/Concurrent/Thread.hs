{-# LANGUAGE CPP, NoImplicitPrelude, UnicodeSyntax #-}

--------------------------------------------------------------------------------
-- |
-- Module     : Control.Concurrent.Thread
-- Copyright  : (c) 2010 Bas van Dijk & Roel van Dijk
-- License    : BSD3 (see the file LICENSE)
-- Maintainer : Bas van Dijk <v.dijk.bas@gmail.com>
--            , Roel van Dijk <vandijk.roel@gmail.com>
--
-- Standard threads extended with the ability to wait for their termination.
--
-- This module exports equivalently named functions from @Control.Concurrent@
-- (and @GHC.Conc@). Avoid ambiguities by importing this module qualified. May
-- we suggest:
--
-- @
-- import qualified Control.Concurrent.Thread as Thread ( ... )
-- @
--
-- The following is an example how to use this module:
--
-- @
--
-- import qualified Control.Concurrent.Thread as Thread ( 'forkIO', 'unsafeResult' )
--
-- main = do (tid, wait) <- Thread.'forkIO' $ do x <- someExpensiveComputation
--                                            return x
--          doSomethingElse
--          x <- Thread.'unsafeResult' =<< 'wait'
--          doSomethingWithResult x
-- @
--
--------------------------------------------------------------------------------

module Control.Concurrent.Thread
  ( -- * Forking threads
    forkIO
  , forkOS
#ifdef __GLASGOW_HASKELL__
  , forkOnIO
#endif

    -- * Results
  , Result
  , unsafeResult
  ) where


--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------

-- from base:
import qualified Control.Concurrent ( forkIO, forkOS )
import Control.Concurrent           ( ThreadId )
import Control.Concurrent.MVar      ( newEmptyMVar, putMVar, readMVar )
import Control.Exception            ( SomeException(SomeException)
                                    , blocked, block, unblock, try, throwIO
                                    )
import Control.Monad                ( return, (>>=), fail )
import Data.Either                  ( Either(..), either )
import Data.Function                ( ($) )
import System.IO                    ( IO )

#ifdef __GLASGOW_HASKELL__
import qualified GHC.Conc           ( forkOnIO )
import Data.Int                     ( Int )
#endif

-- from base-unicode-symbols:
import Data.Function.Unicode        ( (∘) )


--------------------------------------------------------------------------------
-- * Forking threads
--------------------------------------------------------------------------------

{-|
Sparks off a new thread to run the given 'IO' computation and returns the
'ThreadId' of the newly created thread paired with an IO computation that waits
for the result of the thread.

The new thread will be a lightweight thread; if you want to use a foreign
library that uses thread-local storage, use 'forkOS' instead.

GHC note: the new thread inherits the blocked state of the parent (see
'Control.Exception.block').
-}
forkIO ∷ IO α → IO (ThreadId, IO (Result α))
forkIO = fork Control.Concurrent.forkIO

{-|
Like 'forkIO', this sparks off a new thread to run the given 'IO' computation
and returns the 'ThreadId' of the newly created thread paired with an IO
computation that waits for the result of the thread.

Unlike 'forkIO', 'forkOS' creates a /bound/ thread, which is necessary if you
need to call foreign (non-Haskell) libraries that make use of thread-local
state, such as OpenGL (see 'Control.Concurrent').

Using 'forkOS' instead of 'forkIO' makes no difference at all to the scheduling
behaviour of the Haskell runtime system. It is a common misconception that you
need to use 'forkOS' instead of 'forkIO' to avoid blocking all the Haskell
threads when making a foreign call; this isn't the case. To allow foreign calls
to be made without blocking all the Haskell threads (with GHC), it is only
necessary to use the @-threaded@ option when linking your program, and to make
sure the foreign import is not marked @unsafe@.
-}
forkOS ∷ IO α → IO (ThreadId, IO (Result α))
forkOS = fork Control.Concurrent.forkOS

#ifdef __GLASGOW_HASKELL__
{-|
Like 'forkIO', but lets you specify on which CPU the thread is
created.  Unlike a 'forkIO' thread, a thread created by 'forkOnIO'
will stay on the same CPU for its entire lifetime ('forkIO' threads
can migrate between CPUs according to the scheduling policy).
'forkOnIO' is useful for overriding the scheduling policy when you
know in advance how best to distribute the threads.

The 'Int' argument specifies the CPU number; it is interpreted modulo
'numCapabilities' (note that it actually specifies a capability number
rather than a CPU number, but to a first approximation the two are
equivalent).
-}
forkOnIO ∷ Int → IO α → IO (ThreadId, IO (Result α))
forkOnIO = fork ∘ GHC.Conc.forkOnIO
#endif

--------------------------------------------------------------------------------

-- | Internally used function which generalises 'forkIO', 'forkOS' and
-- 'forkOnIO' by parameterizing the function which does the actual forking.
fork ∷ (IO () → IO ThreadId) → (IO α → IO (ThreadId, IO (Result α)))
fork doFork = \a → do
  res ← newEmptyMVar
  parentIsBlocked ← blocked
  tid ← block $ doFork $
    try (if parentIsBlocked then a else unblock a) >>= putMVar res
  return (tid, readMVar res)


--------------------------------------------------------------------------------
-- Results
--------------------------------------------------------------------------------

-- | A result of a thread is either some exception that was thrown in the thread
-- and wasn't catched or the actual value that was returned by the thread.
type Result α = Either SomeException α

{-| Unsafely retrieve the actual value from the result.

When the result is 'SomeException' the exception stored inside of the
'SomeException' is rethrown in the current thread.
-}
unsafeResult ∷ Result α → IO α
unsafeResult = either throwInner return

-- | Throw the exception stored inside the 'SomeException'.
throwInner ∷ SomeException → IO α
throwInner (SomeException e) = throwIO e


-- The End ---------------------------------------------------------------------
