/** Portable protocol/record contracts. Runtime validation is in course-core.js. */
type CourseId = string;
interface Reference { sourceId: string; locator?: {kind:'pdfPage'|'printedPage'|'section'|'lineRange'|'timeRange'|'unknown'; value:string|number|[number,number]}; }
interface CoursePack {files:Record<string,string>;available:Record<string,boolean>;assets:Record<string,string>;base:string;}
interface CourseManifest {schemaVersion:'1.0'|'1.1';courseId:CourseId;contentVersion:string;title:string;language:string;modules:{id:string;title:string;topics:string[]}[];topics:{id:string;file:string}[];scopes?:{id:string;title:string}[];archiveFiles?:{file:string;title:string}[];sources:{id:string;title:string;kind:'pdf'|'text'|'web'|'reference';file?:string;url?:string}[];}
interface LearningRecord {format:'learning-records';version:1;courseId:CourseId;last:string;block:string;sheet:number;notes:Record<string,string>;answers:Record<string,{optionId:string;version:string}>;qa:{id:string;topic:string;question:string;answer:string;status:string;version:string;model:string;time:string;usage?:{input_tokens:number;output_tokens:number}}[];bookmarks:string[];seen:string[];qaDrafts:Record<string,string>;qaDeleted:string[];model:string;modelEpoch:1;large:boolean;}

interface DiagramBlock {id:string;type:'diagram';layout:'flow'|'routes'|'sparse';title?:string;nodes?:{kicker:string;title:string;detailMarkdown:string;dark?:boolean}[];routes?:{label:string;nodes:string[]}[];segments?:{text:string;range:string}[];metrics?:{label:string;value:string}[];captionMarkdown?:string;}

interface MarkdownBlock {id:string;type:'markdown';file:string;role?:'takeaway';visibility?:'visible'|'contextOnly';references?:Reference[];extensions?:Record<string,unknown>;}
