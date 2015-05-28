module Kafka.Client.Consumer
( decodeFtResponse
, packFtRqMessage
, encodeFtRequest
) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Char8 as BC
import Data.Binary.Get
import Data.Binary.Put
import Kafka.Protocol


packTopic :: BS.ByteString -> [Partition] -> RqTopic
packTopic t ps = RqTopic
   (fromIntegral $ BS.length t)
   t
   (fromIntegral $ length ps)
   ps

packFtRequest :: BS.ByteString -> PartitionNumber -> Offset -> Request
packFtRequest t p o = FetchRequest
   (-1)
   0
   0
   1
   [packTopic t [packFtPartition p o]]

packFtPartition :: PartitionNumber -> Offset -> Partition
packFtPartition p o = RqFtPartition
   p
   o
   1048576

packFtRqMessage :: (Int, Int, [Char], [Char], Int, Int) -> RequestMessage
packFtRqMessage (apiV, corr, client, topic, partition, offset) = RequestMessage {
       -- FIXME (meiersi): this line seems to be unnecessarily long. Introduce
       -- local definitions in where clause that have telling names. Also
       -- consider adding explicit type signatures, as the 'fromIntegral'
       -- casting introduces a lot of uncertainty about what is really going
       -- on.
       rqSize = (fromIntegral $ (BL.length $ runPut $ buildFetchRequest $ packFtRequest (BC.pack topic) (fromIntegral partition) (fromIntegral offset))
                              + 2 -- reqApiKey
                              + 2 -- reqApiVersion
                              + 4 -- correlationId
                              + 2 -- clientIdLen
                              + (fromIntegral $ length client) -- clientId
                )
     , rqApiKey = 1
     , rqApiVersion = fromIntegral apiV
     , rqCorrelationId = fromIntegral corr
     , rqClientIdLen = fromIntegral $ length client
     , rqClientId = BC.pack client
     , rqRequest = packFtRequest (BC.pack topic) (fromIntegral partition) (fromIntegral offset)
  }

-------------------
-- Encode / Decode
-------------------

-- FIXME (meiersi): avoid partial functions!
-- FIXME (meiersi): replace magic tuple by a properly named record.
encodeFtRequest :: (Int, Int, Int, String, String, Int, Int) -> RequestMessage
encodeFtRequest (1, apiV, corr, client, topic, partition, offset) = packFtRqMessage (apiV, corr, client, topic, partition, offset)

decodeFtResponse :: BL.ByteString -> ResponseMessage
decodeFtResponse b = runGet fetchResponseMessageParser b
