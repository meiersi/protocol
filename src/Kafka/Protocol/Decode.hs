module Kafka.Protocol.Decode
( messageSetParser
, requestMessageParser

, produceResponseMessageParser
, fetchResponseMessageParser
, metadataResponseMessageParser
)
where

import Kafka.Protocol.Types
import Data.Binary.Get
import Data.Binary.Put
import qualified Data.ByteString.Lazy as BL
import Kafka.Protocol.Encode
import qualified Data.ByteString as BS


--------------------------------------------------------
-- Common
--------------------------------------------------------

parseList :: Int -> (Get a) -> Get [a]
parseList i p = do
  if (i < 1)
    then return []
    else do x <- p
            xs <- parseList (i-1) p
            return (x:xs)

parseMessageSets :: Int -> Get [MessageSet]
parseMessageSets i = do
    if (i < 1)
    then return []
    else do messageSet <- messageSetParser
            messageSets <- parseMessageSets $ i - (fromIntegral $ BL.length $ runPut $ buildMessageSet messageSet)
            return (messageSet:messageSets)


--------------------------------------------------------
-- Data
--------------------------------------------------------


payloadParser :: Get Payload
payloadParser = do
  magic  <- getWord8
  attr   <- getWord8
  keylen <- getWord32be
  paylen <- getWord32be
  payload <- getByteString $ fromIntegral paylen
  return $! Payload magic attr keylen paylen payload

messageParser :: Get Message
messageParser = do
  crc    <- getWord32be
  p      <- payloadParser
  return $! Message crc p

messageSetParser :: Get MessageSet
messageSetParser = do
  offset <- getWord64be
  len <- getWord32be
  message <- messageParser
  return $! MessageSet offset len message


--------------------------------------------------------
-- Request
--------------------------------------------------------

topicNameParser :: Get RqTopicName
topicNameParser = do
  topicNameLen  <- getWord16be
  topicName     <- getByteString $ fromIntegral topicNameLen
  return $ RqTopicName topicNameLen topicName


topicParser :: (Get Partition) -> Get RqTopic
topicParser p = do
  topicNameLen  <- getWord16be
  topicName     <- getByteString $ fromIntegral topicNameLen
  numPartitions <- getWord32be
  partitions    <- parseList (fromIntegral numPartitions) p
  return $ RqTopic topicNameLen topicName numPartitions partitions

------------------------
-- Produce Request (Pr)
------------------------
rqPrPartitionParser = do
  partitionNumber   <- getWord32be
  messageSetSize    <- getWord32be
  messageSets       <- parseMessageSets (fromIntegral messageSetSize)
  return $ RqPrPartition partitionNumber messageSetSize messageSets

produceRequestParser :: Get Request
produceRequestParser = do
  requiredAcks  <- getWord16be
  timeout       <- getWord32be
  numTopics     <- getWord32be
  topics        <- parseList (fromIntegral numTopics) (topicParser rqPrPartitionParser)
  return $ ProduceRequest requiredAcks timeout numTopics topics

---------------------
-- Fetch Request (Ft)
---------------------

rqFtPartitionParser :: Get Partition
rqFtPartitionParser = do
  partitionNumber <- getWord32be
  fetchOffset     <- getWord64be
  maxBytes        <- getWord32be
  return $ RqFtPartition partitionNumber fetchOffset maxBytes

fetchRequestParser :: Get Request
fetchRequestParser = do
  replicaId     <- getWord32be
  maxWaitTime   <- getWord32be
  minBytes      <- getWord32be
  numTopics     <- getWord32be
  topics        <- parseList (fromIntegral numTopics) (topicParser rqFtPartitionParser)
  return $ FetchRequest replicaId maxWaitTime minBytes numTopics topics

------------------------
-- Metadata Request (Md)
------------------------
metadataRequestParser :: Get Request
metadataRequestParser = do
  numTopics     <- getWord32be
  topicNames    <- parseList (fromIntegral numTopics) topicNameParser
  return $ MetadataRequest numTopics topicNames

------------------------
-- Offset Request (Of)
------------------------
offsetRequestParser :: Get Request
offsetRequestParser = do
  replicaId     <- getWord32be
  numTopics     <- getWord32be
  topics        <- parseList (fromIntegral numTopics) (topicParser rqOfPartitionParser)
  return $ OffsetRequest replicaId numTopics topics

rqOfPartitionParser :: Get Partition
rqOfPartitionParser = do
  partition     <- getWord32be
  time          <- getWord64be
  maxNumOfOf    <- getWord32be
  return $ RqOfPartition partition time maxNumOfOf
------------------------
-- Request Message Header (Rq)
------------------------

requestMessageParser :: Get RequestMessage
requestMessageParser = do
  --requestSize   <- getWord32be
  apiKey        <- getWord16be
  apiVersion    <- getWord16be
  correlationId <- getWord32be
  clientIdLen   <- getWord16be
  clientId      <- getByteString $ fromIntegral clientIdLen
  request       <- case (fromIntegral apiKey) of
    0 -> produceRequestParser
    1 -> fetchRequestParser
    3 -> metadataRequestParser
  --request <- produceRequestParser
  return $ RequestMessage 0 apiKey apiVersion correlationId clientIdLen clientId request



--------------------------------------------------------
-- Response
--------------------------------------------------------


rsTopicParser :: (Get RsPayload) -> Get RsTopic
rsTopicParser p = do
  topicNameLen <- getWord16be
  topicName <- getByteString $ fromIntegral topicNameLen
  numPayloads <- getWord32be
  payloads <- parseList (fromIntegral numPayloads) p
  return $ RsTopic topicNameLen topicName numPayloads payloads

---------------------
-- Produce Response (Pr)
---------------------
rsPrErrorParser :: Get RsPayload
rsPrErrorParser= do
  partitionNumber <- getWord32be
  errorCode <- getWord16be
  offset <- getWord64be
  return $! RsPrPayload partitionNumber errorCode offset

produceResponseParser :: Get Response
produceResponseParser = do
  topic <- rsTopicParser rsPrErrorParser
  return $! ProduceResponse topic

produceResponseMessageParser :: Get ResponseMessage
produceResponseMessageParser = do
  correlationId <- getWord32be
  unknown <- getWord32be
  numResponses <- getWord32be
  responses <- parseList (fromIntegral numResponses) produceResponseParser
  return $! ResponseMessage correlationId numResponses responses
---------------------
-- Fetch Response (Ft)
---------------------
fetchResponseMessageParser :: Get ResponseMessage
fetchResponseMessageParser = do
  correlationId <- getWord32be
  unknown <- getWord32be
  numResponses <- getWord32be
  responses <- parseList (fromIntegral numResponses) fetchResponseParser
  return $! ResponseMessage correlationId numResponses responses

fetchResponseParser :: Get Response
fetchResponseParser = do
  topicNameLen <- getWord16be
  topicsName <- getByteString $ fromIntegral topicNameLen
  numPayloads <- getWord32be
  payloads <- parseList (fromIntegral numPayloads) rsFtPayloadParser
  return $! FetchResponse topicNameLen topicsName numPayloads payloads

rsFtPayloadParser :: Get RsPayload
rsFtPayloadParser = do
  partition <- getWord32be
  errorCode <- getWord16be
  hwMarkOffset <- getWord64be
  messageSetSize <- getWord32be
  messageSet <- parseMessageSets (fromIntegral messageSetSize)
  return $! RsFtPayload partition errorCode hwMarkOffset messageSetSize messageSet

---------------------
-- Metdata Response (Md)
---------------------
rsMdPartitionMdParser :: Get RsMdPartitionMetadata
rsMdPartitionMdParser = do
  errorcode <- getWord16be
  partition <- getWord32be
  leader <- getWord32be
  numreplicas <- getWord32be
  replicas <- parseList (fromIntegral numreplicas) getWord32be
  numIsr <- getWord32be
  isrs <- parseList (fromIntegral numIsr) getWord32be
  return $! RsMdPartitionMetadata errorcode partition leader numreplicas replicas numIsr isrs

rsMdPayloadTopicParser :: Get RsPayload
rsMdPayloadTopicParser = do
  errorcode <- getWord16be
  topicNameLen <- getWord16be
  topicName <- getByteString $ fromIntegral topicNameLen
  numPartition <- getWord32be
  partitions <- parseList (fromIntegral numPartition) rsMdPartitionMdParser
  return $! RsMdPayloadTopic errorcode topicNameLen topicName numPartition partitions

rsMdPayloadBrokerParser :: Get RsPayload
rsMdPayloadBrokerParser = do
  node <- getWord32be
  hostLen <- getWord16be
  host <- getByteString $ fromIntegral hostLen
  port <- getWord32be
  return $! RsMdPayloadBroker node hostLen host port

metadataResponseParser :: Get Response
metadataResponseParser = do
  numBrokers <- getWord32be
  brokers <- parseList (fromIntegral numBrokers) rsMdPayloadBrokerParser
  numTopics   <- getWord32be
  topics <- parseList (fromIntegral numTopics) rsMdPayloadTopicParser
  return $! MetadataResponse numBrokers brokers numTopics topics

metadataResponseMessageParser :: Get ResponseMessage
metadataResponseMessageParser = do
  correlationId <- getWord32be
  unknown <- getWord32be
  numResponses <- getWord32be
  responses <- parseList (fromIntegral numResponses) metadataResponseParser
  return $! ResponseMessage correlationId numResponses responses
