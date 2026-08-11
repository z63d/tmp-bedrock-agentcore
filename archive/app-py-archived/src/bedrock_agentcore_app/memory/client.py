"""AgentCore Memory API client for conversation persistence."""

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any

import structlog
from pydantic import BaseModel

logger = structlog.get_logger()


class MessageRole(str, Enum):
    """Message role types for conversation turns."""

    USER = "USER"
    ASSISTANT = "ASSISTANT"
    TOOL = "TOOL"
    OTHER = "OTHER"


class ConversationTurn(BaseModel):
    """A single turn in a conversation."""

    role: MessageRole
    content: str


class MemoryRecord(BaseModel):
    """A memory record from vector search."""

    content: dict[str, Any] | None = None
    score: float | None = None


class AgentCoreMemoryClient:
    """
    Client for AgentCore Memory API.

    Provides methods for storing and retrieving conversation history
    and performing semantic search over memories.
    """

    def __init__(self, region: str, memory_id: str) -> None:
        """
        Initialize the memory client.

        Args:
            region: AWS region
            memory_id: Bedrock AgentCore Memory ID
        """
        self.region = region
        self.memory_id = memory_id
        self._client: Any = None

    def _get_client(self) -> Any:
        """Get or create the Bedrock AgentCore client."""
        if self._client is None:
            import boto3

            self._client = boto3.client(
                "bedrock-agentcore",
                region_name=self.region,
            )
        return self._client

    async def create_event(
        self,
        actor_id: str,
        session_id: str,
        turns: list[ConversationTurn],
    ) -> None:
        """
        Store conversation turns in memory.

        Args:
            actor_id: The actor (user) ID
            session_id: The session ID
            turns: List of conversation turns to store
        """
        client = self._get_client()

        payload = [
            {
                "conversational": {
                    "role": turn.role.value,
                    "content": {"text": turn.content},
                }
            }
            for turn in turns
        ]

        try:
            client.create_event(
                memoryId=self.memory_id,
                actorId=actor_id,
                sessionId=session_id,
                eventTimestamp=datetime.now(timezone.utc),
                payload=payload,
            )
            logger.info(
                "Created memory event",
                memory_id=self.memory_id,
                session_id=session_id,
                turn_count=len(turns),
            )
        except Exception as e:
            logger.error("Failed to create memory event", error=str(e))
            raise

    async def get_recent_events(
        self,
        actor_id: str,
        session_id: str,
        max_results: int = 10,
    ) -> list[dict[str, Any]]:
        """
        Retrieve recent conversation events.

        Args:
            actor_id: The actor (user) ID
            session_id: The session ID
            max_results: Maximum number of events to retrieve

        Returns:
            List of event dictionaries
        """
        client = self._get_client()

        try:
            response = client.list_events(
                memoryId=self.memory_id,
                actorId=actor_id,
                sessionId=session_id,
                includePayloads=True,
                maxResults=max_results,
            )
            events = response.get("events", [])
            logger.info(
                "Retrieved recent events",
                memory_id=self.memory_id,
                session_id=session_id,
                event_count=len(events),
            )
            return events
        except Exception as e:
            logger.error("Failed to retrieve events", error=str(e))
            raise

    async def search_memories(
        self,
        query: str,
        namespace: str = "/",
        top_k: int = 5,
    ) -> list[MemoryRecord]:
        """
        Search memories using vector similarity.

        Args:
            query: The search query
            namespace: Memory namespace
            top_k: Number of results to return

        Returns:
            List of matching memory records
        """
        client = self._get_client()

        try:
            response = client.retrieve_memory_records(
                memoryId=self.memory_id,
                namespace=namespace,
                searchCriteria={
                    "searchQuery": query,
                    "topK": top_k,
                },
            )
            summaries = response.get("memoryRecordSummaries", [])
            records = [
                MemoryRecord(
                    content=s.get("content"),
                    score=s.get("score"),
                )
                for s in summaries
            ]
            logger.info(
                "Searched memories",
                memory_id=self.memory_id,
                query=query[:50],
                result_count=len(records),
            )
            return records
        except Exception as e:
            logger.error("Failed to search memories", error=str(e))
            raise
