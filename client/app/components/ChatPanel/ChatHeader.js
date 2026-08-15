/**
 * ChatHeader — Displays persona name and close button.
 *
 * @param {Object} props
 * @param {string} props.personaName - Name of the AI persona
 * @param {Function} props.onClose - Called when the close button is clicked
 */
import React from 'react';

const ChatHeader = ({ personaName, onClose }) => (
  <div className="chatPanel__header">
    <h3 className="chatPanel__personaName">
      {personaName || 'AI Assistant'}
    </h3>
    <button
      className="chatPanel__closeBtn"
      onClick={onClose}
      aria-label="Close chat"
      type="button"
    >
      {/* Simple X icon via SVG */}
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path
          d="M15 5L5 15M5 5l10 10"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </button>
  </div>
);

export default ChatHeader;
